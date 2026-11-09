// Store-level cookie logic without CEF: the read-back contract and op rounds
// against a fake cookie manager, conversions, and the automation handlers.
#include <cassert>
#include <cstdio>
#include <map>
#include <set>

#include "desktop_cookie_planner.h"
#include "desktop_cookie_store.h"
#include "handlers/cookie_handler.h"
#include "kelpie/desktop_router.h"

using namespace kelpie;
using namespace kelpie::desktop_cookie_store;

namespace {

Json Wire(const std::string& domain, const std::string& name, const std::string& value, Json expires = 4102444800,
          const std::string& path = "/") {
  return {{"domain", domain}, {"path", path}, {"name", name}, {"value", value}, {"expires", expires},
          {"secure", true}, {"httpOnly", true}, {"sameSite", "Lax"}};
}

// A cookie manager with the quirks real engines have.
struct FakeBackend : CookieBackend {
  std::map<std::string, Json> cookies;
  std::set<std::string> refuse;  // names whose writes are refused
  bool host_only_only = false;   // stores ".example.com" as "example.com"
  bool visit_fails = false, apply_fails = false;
  int visits = 0, applies = 0;

  static std::string Key(const Json& c) { return Json::array({c["domain"], c.value("path", "/"), c["name"]}).dump(); }
  void Put(const Json& c) { cookies[Key(c)] = c; }

  bool VisitAll(Json* out, const Cancelled&) override {
    ++visits;
    if (visit_fails) return false;
    *out = Json::array();
    for (const auto& [key, cookie] : cookies) out->push_back(cookie);
    return true;
  }
  std::optional<std::vector<bool>> Apply(const std::vector<Write>& writes, const Cancelled&) override {
    ++applies;
    if (apply_fails) return std::nullopt;
    std::vector<bool> flags;
    for (const auto& write : writes) {
      Json cookie = write.cookie;
      if (write.remove) {
        cookies.erase(Key(cookie));
        flags.push_back(true);
        continue;
      }
      if (refuse.count(cookie["name"])) {
        flags.push_back(false);
        continue;
      }
      if (host_only_only) cookie["domain"] = BareDomain(cookie["domain"]);
      Put(cookie);
      flags.push_back(true);
    }
    return flags;
  }
};

Json Op(int id, const std::string& op, const Json& cookie) { return {{"id", id}, {"op", op}, {"cookie", cookie}}; }

void ReadbackContract() {
  const Json cookies = Json::array({Wire(".a.example.com", "sid", "1"), Wire("a.example.com", "sid", "2"),
                                    Wire("example.com", "sid", "3"), Wire(".a.example.com", "other", "4"),
                                    Wire("A.Example.com", "sid", "5", 1, "/deep")});
  const Json back = Readback(cookies, {{"domain", ".a.example.com"}, {"name", "sid"}});
  assert(back.size() == 3);  // both forms of a.example.com and every path; never the parent domain
  for (const auto& cookie : back) assert(cookie["value"] != "3" && cookie["value"] != "4");
  Json partitioned = Wire("a.example.com", "sid", "6");
  partitioned["partitioned"] = true;
  assert(Readback(Json::array({partitioned}), {{"domain", "a.example.com"}, {"name", "sid"}}).empty());
}

void Rounds() {
  FakeBackend engine;
  engine.Put(Wire(".example.com", "keep", "k"));
  engine.Put(Wire("example.com", "sid", "old"));
  engine.refuse = {"refused"};
  // Two ops on one (host, name) group run in separate rounds, so the first
  // op's read-back reflects only itself.
  const Json ops = Json::array({Op(0, "set", Wire(".example.com", "sid", "new")),
                                Op(1, "delete", {{"domain", "example.com"}, {"path", "/"}, {"name", "sid"}}),
                                Op(2, "set", Wire("other.test", "refused", "x")),
                                Op(3, "delete", {{"domain", ".example.com"}, {"path", "/"}, {"name", "keep"}})});
  const auto results = ApplySyncOps(engine, ops, {});
  assert(results && results->size() == 4);
  assert(engine.applies == 2 && engine.visits == 2);
  const Json& first = (*results)[0];
  assert(first["id"] == 0 && first["ok"] == true && first["readback"].size() == 2);  // the new domain cookie and the old host cookie
  const Json& second = (*results)[1];
  assert(second["ok"] == true && second["readback"].size() == 1 && second["readback"][0]["domain"] == ".example.com");
  assert((*results)[2]["ok"] == false && (*results)[2]["readback"].empty());
  assert((*results)[3]["readback"].empty());

  // A reshaping engine reports the variant under the read-back.
  FakeBackend reshaping;
  reshaping.host_only_only = true;
  const auto reshaped = ApplySyncOps(reshaping, Json::array({Op(0, "set", Wire(".example.com", "sid", "v"))}), {});
  assert(reshaped && (*reshaped)[0]["readback"][0]["domain"] == "example.com");

  // A failed read-back or write is never turned into an empty success.
  FakeBackend broken;
  broken.visit_fails = true;
  assert(!ApplySyncOps(broken, Json::array({Op(0, "set", Wire("a.test", "n", "v"))}), {}));
  broken.visit_fails = false;
  broken.apply_fails = true;
  assert(!ApplySyncOps(broken, Json::array({Op(0, "set", Wire("a.test", "n", "v"))}), {}));
  assert(ApplySyncOps(broken, Json::array(), {})->empty());
  assert(!ApplySyncOps(engine, Json::array({Op(0, "set", Wire("a.test", "n", "v"))}), [] { return true; }));

  Json partitioned = Wire("chips.test", "p", "v");
  partitioned["partitioned"] = true;
  engine.Put(partitioned);
  Json snapshot, coverage;
  assert(SyncSnapshot(engine, &snapshot, &coverage, {}) && coverage == Json({{"all", true}}));
  for (const auto& cookie : snapshot) assert(cookie["domain"] != "chips.test");
  broken.visit_fails = true;
  assert(!SyncSnapshot(broken, &snapshot, &coverage, {}));
}

Json Info(const std::string& domain, const std::string& name, Json expires = "2030-01-01T00:00:00.000Z") {
  return {{"name", name}, {"value", "v"}, {"domain", domain}, {"path", "/"}, {"expires", expires},
          {"httpOnly", true}, {"secure", true}, {"sameSite", "Lax"}};
}

void Conversions() {
  const Json wire = Wire(".example.com", "sid", "v", 1893456000, "/app");
  const Json automation = ToAutomation(wire);
  assert(automation["expires"] == "2030-01-01T00:00:00.000Z" && automation["sameSite"] == "Lax" &&
         !automation.contains("session") && automation.size() == 8);
  assert(FromAutomation(automation).wire == wire);  // get-cookies output writes back unchanged
  const Json session = ToAutomation(Wire("host.example", "s", "v", nullptr));
  assert(session["expires"].is_null() && FromAutomation(session).wire->at("expires").is_null());
  assert(ToAutomation(Wire("a.test", "n", "v", 951782400))["expires"] == "2000-02-29T00:00:00.000Z");
  assert(ToAutomation(Wire("a.test", "n", "v", 86399))["expires"] == "1970-01-01T23:59:59.000Z");

  auto parsed = FromAutomation(Info("Host.Example", "a"));
  assert(parsed.wire && (*parsed.wire)["domain"] == "host.example" && (*parsed.wire)["expires"] == 1893456000);
  Json unspecified = Info(".a.test", "b", nullptr);
  unspecified["sameSite"] = "Unspecified";
  assert(FromAutomation(unspecified).wire->at("sameSite") == "Unspecified");
  // Every field is required and strictly typed.
  for (const char* missing : {"name", "value", "domain", "path", "expires", "httpOnly", "secure", "sameSite"}) {
    Json bad = Info("a.test", "n");
    bad.erase(missing);
    assert(!FromAutomation(bad).wire && !FromAutomation(bad).error.empty());
  }
  const auto broken = [](const char* key, Json value) {
    Json bad = Info("a.test", "n");
    bad[key] = std::move(value);
    return !FromAutomation(bad).wire;
  };
  assert(broken("name", "") && broken("value", 3) && broken("domain", ".") && broken("domain", "a.test/x"));
  assert(broken("path", "app") && broken("expires", 1893456000.5) && broken("expires", -5) && broken("expires", "tomorrow"));
  Json seconds = Info("a.test", "n", 1893456000);
  assert(FromAutomation(seconds).wire->at("expires") == 1893456000);  // whole Unix seconds are accepted too
  assert(broken("sameSite", "lax") && broken("sameSite", "sometimes") && broken("secure", "yes"));
  assert(broken("value", std::string(5000, 'v')));

  assert(DomainMatches(".example.com", "example.com") && DomainMatches("a.b.example.com", ".EXAMPLE.com"));
  assert(!DomainMatches("badexample.com", "example.com") && !DomainMatches("example.com", "a.example.com"));
  Json scoped = Info("app.example.com", "deep");
  scoped["path"] = "/account";
  Json insecure = Info("example.com", "plain");
  insecure["secure"] = false;
  const Json listed = Json::array({Info(".example.com", "sid"), scoped, insecure, Info("example.org", "sid")});
  assert(Filter(listed, std::string("example.com"), std::nullopt).size() == 3);
  assert(Filter(listed, std::string("example.com"), std::string("sid")).size() == 1);
  assert(Filter(listed, std::nullopt, std::nullopt).size() == 4);
  // url: domain match, path match, Secure only over https.
  assert(Filter(listed, std::nullopt, std::nullopt, std::string("https://app.example.com/account/x")).size() == 2);
  assert(Filter(listed, std::nullopt, std::nullopt, std::string("https://app.example.com/accounts")).size() == 1);
  assert(Filter(listed, std::nullopt, std::nullopt, std::string("http://example.com/")).size() == 1);
  assert(Filter(listed, std::string("example.com"), std::nullopt, std::string("https://example.com/")).size() == 2);
  assert(!MatchesUrl(Json::object(), "ftp://example.com/") && !MatchesUrl(Json::object(), "example.com"));
  // The tab path's filter uses the same domain rule.
  assert(desktop_cookie::MatchesFilter({{"name", "sid"}, {"domain", ".app.example.com"}}, {{"domain", "example.com"}}));
  assert(!desktop_cookie::MatchesFilter({{"name", "sid"}, {"domain", "example.org"}}, {{"domain", "example.com"}}));
}

void WritesAndCopies() {
  std::string error;
  Json bad = Json::array({Info(".a.test", "ok"), Info("a.test", "bad")});
  bad[1]["sameSite"] = "?";
  assert(!ParseCookies(bad, &error) && error.rfind("cookies[1]: ", 0) == 0);
  const auto parsed = ParseCookies(Json::array({Info(".a.test", "ok"), Info("a.test", "refused"), Info("b.test", "ok2")}),
                                   &error);
  assert(parsed && parsed->size() == 3);
  FakeBackend store;
  store.refuse = {"refused"};
  const Json written = WriteCookies(store, *parsed, {});
  assert(written["set"] == 2 && written["failed"].size() == 1);
  assert(written["failed"][0] == Json({{"index", 1}, {"name", "refused"}, {"domain", "a.test"}, {"error", "NOT_STORED"}}));
  assert(store.cookies.size() == 2);

  FakeBackend source, target;
  source.Put(Wire(".example.com", "sid", "1"));
  source.Put(Wire("app.example.com", "pref", "2"));
  source.Put(Wire("example.org", "other", "3"));
  source.Put(Wire("example.com", "refused", "5"));
  Json partitioned = Wire("example.com", "chips", "4");
  partitioned["partitioned"] = true;
  source.Put(partitioned);
  target.refuse = {"refused"};
  target.Put(Wire(".example.com", "sid", "old"));
  const auto copied = CopyCookies(source, target, std::string("example.com"), {});
  assert(copied && (*copied)["copied"] == 2 && (*copied)["failed"].size() == 1);
  assert((*copied)["failed"][0] == Json({{"name", "refused"}, {"domain", "example.com"}, {"error", "NOT_STORED"}}));
  assert(target.cookies.size() == 2 && target.cookies[FakeBackend::Key(Wire(".example.com", "sid", ""))]["value"] == "1");
  source.visit_fails = true;
  assert(!CopyCookies(source, target, std::nullopt, {}));
}

// Only what the cookie handlers call; everything else is unsupported.
struct FakeControl : DesktopBrowserControl {
  CookieStoreTarget last_target, last_to;
  std::optional<std::string> last_domain;
  Json last_written;
  int reads = 0, writes = 0, copies = 0;
  BrowserControlResult ReadCookieStore(const CookieStoreTarget& target, Json* out, Timeout) override {
    ++reads;
    last_target = target;
    *out = Json::array({ToAutomation(Wire(".example.com", "sid", "1")), ToAutomation(Wire("example.org", "x", "2")),
                        ToAutomation(Wire("example.com", "plain", "3"))});
    return BrowserControlResult::Success();
  }
  BrowserControlResult WriteCookieStore(const CookieStoreTarget& target, const Json& cookies, Json* out, Timeout) override {
    ++writes;
    last_target = target;
    last_written = cookies;
    *out = {{"set", cookies.size()}, {"failed", Json::array()}};
    return BrowserControlResult::Success();
  }
  BrowserControlResult CopyCookieStore(const CookieStoreTarget& from, const CookieStoreTarget& to,
                                       const std::optional<std::string>& domain, Json* out, Timeout) override {
    ++copies;
    last_target = from;
    last_to = to;
    last_domain = domain;
    *out = {{"copied", 1}, {"failed", Json::array()}};
    return BrowserControlResult::Success();
  }
  BrowserControlResult Unsupported() { return BrowserControlResult::Failure("UNSUPPORTED", "fake"); }
  BrowserControlResult GetTabs(std::vector<TabSnapshot>*, Timeout) override { return Unsupported(); }
  BrowserControlResult ResolveTab(const std::optional<std::string>&, const std::optional<std::uint64_t>&, TabLease*,
                                  Timeout) override { return Unsupported(); }
  BrowserControlResult CreateTab(const NewTabRequest&, TabSnapshot*, Timeout) override { return Unsupported(); }
  using DesktopBrowserControl::CreateTab;
  BrowserControlResult ActivateTab(TabLease, Timeout) override { return Unsupported(); }
  BrowserControlResult CloseTab(TabLease, Timeout) override { return Unsupported(); }
  BrowserControlResult Navigate(std::optional<TabLease>, std::string, TabSnapshot*, Timeout) override { return Unsupported(); }
  BrowserControlResult Back(TabLease, TabSnapshot*, Timeout) override { return Unsupported(); }
  BrowserControlResult Forward(TabLease, TabSnapshot*, Timeout) override { return Unsupported(); }
  BrowserControlResult Reload(TabLease, TabSnapshot*, Timeout) override { return Unsupported(); }
  BrowserControlResult Evaluate(TabLease, std::string, Json*, Timeout) override { return Unsupported(); }
  BrowserControlResult Screenshot(TabLease, BrowserScreenshot*, Timeout) override { return Unsupported(); }
  BrowserControlResult GetCookies(TabLease, const Json&, Json*, Timeout) override { return Unsupported(); }
  BrowserControlResult SetCookies(TabLease, const Json&, Json*, Timeout) override { return Unsupported(); }
  BrowserControlResult DeleteCookies(TabLease, const Json&, Json*, Timeout) override { return Unsupported(); }
  BrowserControlResult DispatchTrustedInput(TabLease, const Json&, Json*, Timeout) override { return Unsupported(); }
  BrowserControlResult GetDialog(TabLease, Json*, Timeout) override { return Unsupported(); }
  BrowserControlResult HandleDialog(TabLease, const Json&, Json*, Timeout) override { return Unsupported(); }
  BrowserControlResult DevTools(TabLease, std::string, const Json&, Json*, Timeout) override { return Unsupported(); }
};

void Handlers() {
  FakeControl control;
  DesktopHandlerRuntime runtime;
  runtime.browser_control = &control;
  DesktopRouter router;
  const CookieHandler handler(runtime);  // routes capture the handler; it must outlive them
  handler.Register(router);

  auto result = router.Dispatch("get-cookies", {{"all", true}, {"domain", "example.com"}});
  assert(result.status_code == 200 && result.body["complete"] == true && result.body["cookies"].size() == 2 &&
         result.body["count"] == 2);
  assert(result.body["cookies"][0]["expires"] == "2100-01-01T00:00:00.000Z");
  assert(!control.last_target.tab_id && !control.last_target.partition);
  result = router.Dispatch("get-cookies", {{"partition", "work"}, {"name", "sid"}});
  assert(result.status_code == 200 && control.last_target.partition == std::optional<std::string>("work") &&
         result.body["count"] == 1 && !result.body.contains("complete"));
  result = router.Dispatch("get-cookies", {{"all", true}, {"url", "https://example.com/"}});
  assert(result.status_code == 200 && result.body["count"] == 2);
  result = router.Dispatch("get-cookies", {{"all", true}, {"tabId", "tab-2"}, {"generation", 3}});
  assert(result.status_code == 200 && control.last_target.tab_id == std::optional<std::string>("tab-2") &&
         control.last_target.generation == std::optional<std::uint64_t>(3));
  assert(router.Dispatch("get-cookies", {{"all", true}, {"url", "example.com"}}).status_code == 400);
  assert(router.Dispatch("get-cookies", {{"all", true}, {"tabId", "t"}, {"partition", "p"}}).status_code == 400);
  assert(router.Dispatch("get-cookies", {{"all", "yes"}}).status_code == 400);
  assert(router.Dispatch("get-cookies", {{"all", true}, {"domain", ""}}).status_code == 400);
  assert(control.reads == 4);

  result = router.Dispatch("set-cookies", {{"cookies", Json::array({Info(".a.test", "a")})}, {"partition", "work"}});
  assert(result.status_code == 200 && result.body["set"] == 1 && control.last_target.partition == std::optional<std::string>("work"));
  assert(control.last_written[0]["domain"] == ".a.test" && control.last_written[0]["expires"] == 1893456000);
  // A malformed cookie fails only itself (INVALID_COOKIE); the rest are still written.
  Json mixed = Json::array({Info(".a.test", "a"), {{"name", "b"}, {"domain", "a.test"}}});
  result = router.Dispatch("set-cookies", {{"cookies", mixed}});
  assert(result.status_code == 200 && control.writes == 2 && control.last_written.size() == 1);
  assert(result.body["failed"] ==
         Json::array({{{"index", 1}, {"name", "b"}, {"domain", "a.test"}, {"error", "INVALID_COOKIE"}}}));
  // Nothing valid: nothing is written, every cookie is reported.
  result = router.Dispatch("set-cookies", {{"cookies", Json::array({{{"name", "a"}}})}});
  assert(result.status_code == 200 && result.body["set"] == 0 && result.body["failed"].size() == 1 && control.writes == 2);
  assert(router.Dispatch("set-cookies", {{"cookies", Json::array()}}).status_code == 400);
  assert(router.Dispatch("set-cookies", {{"cookies", Json::array({{{"name", "a"}}})}, {"generation", 1}}).status_code == 400);
  Json many = Json::array();
  for (int i = 0; i < 501; ++i) many.push_back(Info("a.test", "n"));
  assert(router.Dispatch("set-cookies", {{"cookies", many}}).status_code == 400);
  assert(control.writes == 2);

  result = router.Dispatch("copy-cookies", {{"from", Json::object()}, {"to", {{"partition", "work"}}}, {"domain", "example.com"}});
  assert(result.status_code == 200 && result.body["copied"] == 1 && !control.last_target.partition &&
         control.last_to.partition == std::optional<std::string>("work") &&
         control.last_domain == std::optional<std::string>("example.com"));
  result = router.Dispatch("copy-cookies", {{"from", {{"partition", "work"}}}, {"to", {{"partition", "work"}}}});
  assert(result.status_code == 400 && result.body["error"]["code"] == "INVALID_PARAMS");
  assert(router.Dispatch("copy-cookies", {{"from", Json::object()}, {"to", Json::object()}}).body["error"]["code"] ==
         "INVALID_PARAMS");
  assert(router.Dispatch("copy-cookies", {{"from", Json::object()}}).status_code == 400);
  assert(router.Dispatch("copy-cookies", {{"from", "default"}, {"to", Json::object()}}).status_code == 400);
  assert(control.copies == 1);

  result = router.Dispatch("get-cookie-sync-status", Json::object());
  assert(result.status_code == 200 && result.body["supported"] == false && result.body["reason"] == "no-cef" &&
         result.body["listening"] == false && result.body["peers"].empty() && result.body["store"]["warming"] == false);
  runtime.cookie_sync_status = [] { return Json{{"supported", true}, {"signedIn", false}}; };
  DesktopRouter with_sync;
  const CookieHandler sync_handler(runtime);
  sync_handler.Register(with_sync);
  result = with_sync.Dispatch("get-cookie-sync-status", Json::object());
  assert(result.status_code == 200 && result.body["supported"] == true && result.body["signedIn"] == false);
}

}  // namespace

int main() {
  ReadbackContract();
  Rounds();
  Conversions();
  WritesAndCopies();
  Handlers();
  std::puts("test_desktop_cookie_store passed");
  return 0;
}
