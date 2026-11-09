#include "desktop_cookie_store_cef.h"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <condition_variable>
#include <functional>
#include <memory>
#include <mutex>

#include "include/cef_task.h"

namespace kelpie {
namespace {

using Json = nlohmann::json;
using Clock = std::chrono::steady_clock;

// base::Time is microseconds since 1601-01-01 UTC.
constexpr std::int64_t kUnixEpochMicros = 11644473600LL * 1000000LL;
constexpr auto kMaxWait = std::chrono::seconds(10);

class FunctionTask final : public CefTask {
 public:
  explicit FunctionTask(std::function<void()> body) : body_(std::move(body)) {}
  void Execute() override { body_(); }

 private:
  std::function<void()> body_;
  IMPLEMENT_REFCOUNTING(FunctionTask);
};

// Shared between the waiting thread and the CEF UI thread.
struct Completion {
  std::mutex mutex;
  std::condition_variable ready;
  bool done = false;
  bool failed = false;
  Json cookies = Json::array();
  std::vector<int> results;  // -1 pending, 0 refused, 1 accepted
  std::size_t remaining = 0;

  void Finish(bool failure) {
    {
      std::lock_guard lock(mutex);
      failed = failed || failure;
      done = true;
    }
    ready.notify_all();
  }
};

// Waits off the UI thread until `state` completes, the call is cancelled or
// the bound runs out.
bool Await(const std::shared_ptr<Completion>& state, const desktop_cookie_store::Cancelled& cancelled) {
  const auto until = Clock::now() + kMaxWait;
  std::unique_lock lock(state->mutex);
  while (!state->done) {
    if ((cancelled && cancelled()) || Clock::now() >= until) return false;
    state->ready.wait_for(lock, std::chrono::milliseconds(20));
  }
  return !state->failed;
}

class Visitor final : public CefCookieVisitor {
 public:
  explicit Visitor(std::shared_ptr<Completion> state) : state_(std::move(state)) {}
  // CEF releases the visitor once enumeration ends, including when the store is empty.
  ~Visitor() override { state_->Finish(false); }
  bool Visit(const CefCookie& cookie, int, int, bool&) override {
    std::lock_guard lock(state_->mutex);
    state_->cookies.push_back(CefCookieToWire(cookie));
    return true;
  }

 private:
  std::shared_ptr<Completion> state_;
  IMPLEMENT_REFCOUNTING(Visitor);
};

class SetCallback final : public CefSetCookieCallback {
 public:
  SetCallback(std::shared_ptr<Completion> state, std::size_t index) : state_(std::move(state)), index_(index) {}
  void OnComplete(bool success) override { Record(state_, index_, success); }

  static void Record(const std::shared_ptr<Completion>& state, std::size_t index, bool success) {
    bool finished = false;
    {
      std::lock_guard lock(state->mutex);
      if (state->results[index] != -1) return;
      state->results[index] = success ? 1 : 0;
      finished = --state->remaining == 0;
    }
    if (finished) state->Finish(false);
  }

 private:
  std::shared_ptr<Completion> state_;
  std::size_t index_;
  IMPLEMENT_REFCOUNTING(SetCallback);
};

std::string Lower(std::string text) {
  std::transform(text.begin(), text.end(), text.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return text;
}

}  // namespace

Json CefCookieToWire(const CefCookie& cookie) {
  std::string path = CefString(&cookie.path).ToString();
  if (path.empty()) path = "/";
  Json expires = nullptr;
  if (cookie.has_expires) {
    const std::int64_t micros = cookie.expires.val - kUnixEpochMicros;
    expires = micros >= 0 ? micros / 1000000 : -((-micros + 999999) / 1000000);
  }
  const char* same_site = "Unspecified";
  switch (cookie.same_site) {
    case CEF_COOKIE_SAME_SITE_NO_RESTRICTION: same_site = "None"; break;
    case CEF_COOKIE_SAME_SITE_LAX_MODE: same_site = "Lax"; break;
    case CEF_COOKIE_SAME_SITE_STRICT_MODE: same_site = "Strict"; break;
    default: break;
  }
  // CefCookie carries no partition key, so partitioned (CHIPS) cookies cannot
  // be told apart here; see the adapter report.
  return {{"domain", Lower(CefString(&cookie.domain).ToString())},
          {"path", path},
          {"name", CefString(&cookie.name).ToString()},
          {"value", CefString(&cookie.value).ToString()},
          {"expires", expires},
          {"secure", cookie.secure != 0},
          {"httpOnly", cookie.httponly != 0},
          {"sameSite", same_site}};
}

CefCookie WireToCefCookie(const Json& wire, bool remove, std::string* url) {
  CefCookie cookie;
  const std::string domain = Lower(wire.value("domain", std::string()));
  const bool domain_cookie = !domain.empty() && domain.front() == '.';
  std::string host = domain_cookie ? domain.substr(1) : domain;
  if (host.find(':') != std::string::npos && host.front() != '[') host = "[" + host + "]";
  // https lets a write replace or delete a Secure cookie of the same key.
  *url = "https://" + host + "/";
  CefString(&cookie.name) = wire.value("name", std::string());
  CefString(&cookie.value) = remove ? std::string() : wire.value("value", std::string());
  if (domain_cookie) CefString(&cookie.domain) = domain;  // empty = host-only
  CefString(&cookie.path) = wire.value("path", std::string("/"));
  cookie.secure = remove || wire.value("secure", false);
  cookie.httponly = remove || wire.value("httpOnly", false);
  const Json& expires = wire.value("expires", Json());
  if (remove) {
    cookie.has_expires = 1;
    cookie.expires.val = kUnixEpochMicros + 1000000;  // 1970-01-01T00:00:01Z: already expired
  } else if (expires.is_number_integer()) {
    cookie.has_expires = 1;
    cookie.expires.val = kUnixEpochMicros + expires.get<std::int64_t>() * 1000000;
  }
  const std::string same_site = remove ? std::string("Unspecified") : wire.value("sameSite", std::string("Unspecified"));
  cookie.same_site = same_site == "None" ? CEF_COOKIE_SAME_SITE_NO_RESTRICTION
                     : same_site == "Lax" ? CEF_COOKIE_SAME_SITE_LAX_MODE
                     : same_site == "Strict" ? CEF_COOKIE_SAME_SITE_STRICT_MODE
                                             : CEF_COOKIE_SAME_SITE_UNSPECIFIED;
  cookie.priority = CEF_COOKIE_PRIORITY_MEDIUM;
  return cookie;
}

CefCookieBackend::CefCookieBackend(CefRefPtr<CefCookieManager> manager) : manager_(std::move(manager)) {}

bool CefCookieBackend::VisitAll(Json* cookies, const desktop_cookie_store::Cancelled& cancelled) {
  if (!manager_ || CefCurrentlyOn(TID_UI)) return false;
  auto state = std::make_shared<Completion>();
  CefRefPtr<CefCookieManager> manager = manager_;
  const bool posted = CefPostTask(TID_UI, new FunctionTask([manager, state] {
    CefRefPtr<Visitor> visitor = new Visitor(state);
    if (!manager->VisitAllCookies(visitor)) state->Finish(true);
  }));
  if (!posted || !Await(state, cancelled)) return false;
  std::lock_guard lock(state->mutex);
  *cookies = std::move(state->cookies);
  return true;
}

std::optional<std::vector<bool>> CefCookieBackend::Apply(const std::vector<Write>& writes,
                                                          const desktop_cookie_store::Cancelled& cancelled) {
  if (!manager_ || CefCurrentlyOn(TID_UI)) return std::nullopt;
  if (writes.empty()) return std::vector<bool>();
  auto state = std::make_shared<Completion>();
  state->results.assign(writes.size(), -1);
  state->remaining = writes.size();
  CefRefPtr<CefCookieManager> manager = manager_;
  const bool posted = CefPostTask(TID_UI, new FunctionTask([manager, state, writes] {
    for (std::size_t i = 0; i < writes.size(); ++i) {
      std::string url;
      const CefCookie cookie = WireToCefCookie(writes[i].cookie, writes[i].remove, &url);
      // false: an invalid URL or an inaccessible store; the callback never runs.
      if (!manager->SetCookie(url, cookie, new SetCallback(state, i))) SetCallback::Record(state, i, false);
    }
  }));
  if (!posted || !Await(state, cancelled)) return std::nullopt;
  std::lock_guard lock(state->mutex);
  std::vector<bool> flags;
  for (const int result : state->results) flags.push_back(result == 1);
  return flags;
}

}  // namespace kelpie
