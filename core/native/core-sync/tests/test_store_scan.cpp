#include <cassert>
#include <fstream>
#include <string>

#include "sync_harness.h"

using namespace kelpie::sync;
using namespace kelpie::sync::testing;

namespace {

constexpr std::int64_t kNow = 1767225600000;  // 2026-01-01T00:00:00Z

json EntriesOnDisk(const Device& device) {
  std::ifstream input(std::filesystem::u8path(device.path));
  json file = json::parse(input);
  return file["entries"];
}

json FindStored(const Device& device, const std::string& name) {
  for (const auto& entry : EntriesOnDisk(device)) {
    if (entry["n"] == name) return entry;
  }
  return nullptr;
}

void TestFirstSignInAdoptsWithZeroVersion() {
  Device a("first-sign-in");
  a.engine.Put(MakeCookie(".example.com", "sid", "before-sync"));
  a.Open(false, kNow);
  const json result = a.Scan(kNow);
  assert(result["changed"] == 1);
  const json stored = FindStored(a, "sid");
  assert(stored["v"][0] == 0 && stored["v"][1] == 0);
  // The file never contains cookie values.
  std::ifstream input(std::filesystem::u8path(a.path));
  const std::string raw((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
  assert(raw.find("before-sync") == std::string::npos);
}

void TestLocalEditsAndDeletions() {
  Device a("edits");
  a.Open(false, kNow);
  a.Scan(kNow);  // empty first scan
  a.engine.Put(MakeCookie(".example.com", "sid", "one"));
  a.Scan(kNow + 1000);
  json stored = FindStored(a, "sid");
  assert(stored["v"][0] == kNow + 1000);

  a.engine.Put(MakeCookie(".example.com", "sid", "two"));
  a.Scan(kNow + 2000);
  stored = FindStored(a, "sid");
  assert(stored["v"][0] == kNow + 2000);

  const json unchanged = a.Scan(kNow + 3000);
  assert(unchanged["changed"] == 0);

  a.engine.Remove(".example.com", "sid");
  a.Scan(kNow + 4000);
  stored = FindStored(a, "sid");
  assert(stored["del"] == true && stored["v"][0] == kNow + 4000);
}

void TestExpiredCookiesAreDroppedNotTombstoned() {
  Device a("expired");
  a.Open(false, kNow);
  a.Scan(kNow);
  a.engine.Put(MakeCookie(".example.com", "short", "v", kNow / 1000 + 10));
  a.Scan(kNow + 1000);
  a.engine.Remove(".example.com", "short");
  a.Scan(kNow + 20000);
  assert(FindStored(a, "short").is_null());
}

void TestPurgeGuard() {
  Device a("purge");
  a.Open(false, kNow);
  a.Scan(kNow);
  for (int i = 0; i < 40; ++i) a.engine.Put(MakeCookie(".site" + std::to_string(i) + ".com", "c", "v"));
  a.Scan(kNow + 1000);
  a.engine.cookies.clear();  // clear-all, ITP purge or eviction
  const json result = a.Scan(kNow + 2000);
  assert(result["purge"] == true);
  assert(result["changed"] == 0);
  assert(EntriesOnDisk(a).empty());

  // A normal logout (a handful of cookies) still produces tombstones.
  for (int i = 0; i < 40; ++i) a.engine.Put(MakeCookie(".site" + std::to_string(i) + ".com", "c", "v"));
  a.Scan(kNow + 3000);
  a.engine.Remove(".site1.com", "c");
  a.engine.Remove(".site2.com", "c");
  const json logout = a.Scan(kNow + 4000);
  assert(logout["purge"] == false && logout["changed"] == 2);
}

void TestUrlCoverageNeverInventsDeletions() {
  Device a("coverage");
  a.Open(false, kNow);
  a.Scan(kNow);
  a.engine.Put(MakeCookie(".example.com", "root", "v"));
  a.engine.Put(MakeCookie(".example.com", "acct", "v", 4102444800, "/account"));
  a.Scan(kNow + 1000);

  // Android queried only https://example.com/, which cannot return /account.
  json visible = json::array({MakeCookie(".example.com", "root", "v")});
  json result = a.store->Scan(visible, json{{"urls", {"https://example.com/"}}}, kNow + 2000);
  assert(result["changed"] == 0);
  assert(FindStored(a, "acct").contains("del") == false);

  // Querying the path does observe it, so its absence is now a deletion.
  result = a.store->Scan(visible, json{{"urls", {"https://example.com/", "https://example.com/account"}}},
                         kNow + 3000);
  assert(result["changed"] == 1);
  assert(FindStored(a, "acct")["del"] == true);
}

void TestLaunchWarmupAndSessionCookies() {
  Device a("launch");
  a.Open(false, kNow);
  a.engine.Put(MakeCookie(".example.com", "session", "v", std::nullopt));
  a.engine.Put(MakeCookie(".example.com", "persistent", "v"));
  a.Scan(kNow);

  // Restart: the engine lost the session cookie.
  a.engine.Remove(".example.com", "session");
  a.Open(true, kNow + 60000);
  assert(FindStored(a, "session").is_null());  // forgotten at open, so a peer can restore it
  assert(a.Scan(kNow + 61000)["deferred"] == true);

  // A cookie the site set during warm-up must not beat a peer's version.
  a.engine.Put(MakeCookie(".example.com", "anon", "fresh"));
  a.engine.Remove(".example.com", "persistent");  // the store may report empty early
  a.store->FinishWarmup();
  const json first = a.Scan(kNow + 62000);
  assert(FindStored(a, "anon")["v"][0] == 0);
  assert(FindStored(a, "persistent").is_null());  // dropped, not tombstoned
  assert(first["changed"] == 1);
}

void TestSignInLaterKeepsSessionEntries() {
  Device a("sign-in-later");
  a.Open(false, kNow);
  a.engine.Put(MakeCookie(".example.com", "session", "v", std::nullopt));
  a.Scan(kNow);
  // Signed out of Kelpie, logged out of the site, signed back in: no restart.
  a.engine.Remove(".example.com", "session");
  a.Open(false, kNow + 60000);
  a.Scan(kNow + 61000);
  assert(FindStored(a, "session")["del"] == true);
}

void TestForeignSubjectStaysLocal() {
  Device a("foreign");
  a.Open(false, kNow);
  a.engine.Put(MakeCookie(".bank.com", "alice", "secret"));
  a.Scan(kNow);
  a.Open(false, kNow + 1000, "bob");
  a.Scan(kNow + 2000);
  assert(FindStored(a, "alice")["lo"] == true);
  // A rotation of Alice's cookie keeps it local.
  a.engine.Put(MakeCookie(".bank.com", "alice", "rotated"));
  a.Scan(kNow + 3000);
  assert(FindStored(a, "alice")["lo"] == true);
  // Bob's own new cookie syncs.
  a.engine.Put(MakeCookie(".mail.com", "bob", "v"));
  a.Scan(kNow + 4000);
  assert(!FindStored(a, "bob").contains("lo"));
  const json pull = {{"op", "pull"}, {"replica", "peer"}, {"since", {{"replica", a.replica}, {"seq", 0}}}, {"wait", 0}};
  const json response = a.store->AnswerPull(pull, a.engine.Snapshot(), json{{"all", true}}, kNow + 5000);
  assert(response["records"].size() == 1 && response["records"][0]["name"] == "bob");
}

void TestCorruptFileIsReplaced() {
  Device a("corrupt");
  {
    std::filesystem::create_directories(std::filesystem::u8path(a.path).parent_path());
    std::ofstream out(std::filesystem::u8path(a.path));
    out << "{not json";
  }
  a.engine.Put(MakeCookie(".example.com", "sid", "v"));
  a.Open(false, kNow);
  a.Scan(kNow);
  assert(FindStored(a, "sid")["v"][0] == 0);
}

void TestTombstonesSurviveRestart() {
  Device a("tombstones");
  a.Open(false, kNow);
  a.engine.Put(MakeCookie(".example.com", "sid", "v"));
  a.Scan(kNow);
  a.Scan(kNow + 1);
  a.engine.Remove(".example.com", "sid");
  a.Scan(kNow + 1000);
  a.Open(true, kNow + 86400000LL * 400);
  assert(FindStored(a, "sid")["del"] == true);
}

}  // namespace

int main() {
  return RunGuarded([] {
    TestFirstSignInAdoptsWithZeroVersion();
    TestLocalEditsAndDeletions();
    TestExpiredCookiesAreDroppedNotTombstoned();
    TestPurgeGuard();
    TestUrlCoverageNeverInventsDeletions();
    TestLaunchWarmupAndSessionCookies();
    TestSignInLaterKeepsSessionEntries();
    TestForeignSubjectStaysLocal();
    TestCorruptFileIsReplaced();
    TestTombstonesSurviveRestart();
  });
}
