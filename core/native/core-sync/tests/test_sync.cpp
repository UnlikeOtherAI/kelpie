#include <cassert>
#include <string>

#include "sync_harness.h"

using namespace kelpie::sync;
using namespace kelpie::sync::testing;

namespace {

constexpr std::int64_t kNow = 1767225600000;

void Ready(Device& device, std::int64_t now) {
  device.Open(false, now);
  device.Scan(now);
}

void TestLoginAndLogoutPropagate() {
  Device a("a-login"), b("b-login");
  Ready(a, kNow);
  Ready(b, kNow);
  a.engine.Put(MakeCookie(".example.com", "sid", "logged-in"));
  a.Scan(kNow + 1000);
  Sync(b, a, kNow + 2000);
  assert(b.engine.ValueOf(".example.com", "sid") == "logged-in");

  a.engine.Remove(".example.com", "sid");
  a.Scan(kNow + 3000);
  Sync(b, a, kNow + 4000);
  assert(!b.engine.Has(".example.com", "sid"));

  // B's next scan sees nothing new: the write it received is not a local edit.
  assert(b.Scan(kNow + 5000)["changed"] == 0);
}

void TestPushCarriesInitiatorChanges() {
  Device a("a-push"), b("b-push");
  Ready(a, kNow);
  Ready(b, kNow);
  Sync(a, b, kNow + 100);  // establishes watermarks
  a.engine.Put(MakeCookie(".example.com", "from-initiator", "v"));
  a.Scan(kNow + 1000);
  PushAll(a, b, kNow + 2000);
  assert(b.engine.Has(".example.com", "from-initiator"));
  // B's watermark of A moved only after commit, and a second push is empty.
  const json built = a.store->BuildPush(b.store->Watermark(a.replica), a.engine.Snapshot(), json{{"all", true}},
                                        kNow + 3000);
  assert(built["push"].is_null());
}

void TestEchoGuardWithNormalisingEngine() {
  Device a("a-echo"), b("b-echo");
  b.engine.drops_same_site = true;
  Ready(a, kNow);
  Ready(b, kNow);
  a.engine.Put(MakeCookie(".example.com", "sid", "v"));
  a.Scan(kNow + 1000);
  Sync(b, a, kNow + 2000);
  // B stored it as Unspecified but must not treat that as a new local edit.
  assert(b.Scan(kNow + 3000)["changed"] == 0);
  Sync(a, b, kNow + 4000);
  assert(a.Scan(kNow + 5000)["changed"] == 0);
}

void TestThirdDeviceGetsTheAcceptedRecord() {
  Device a("a-relay"), b("b-relay"), c("c-relay");
  b.engine.drops_same_site = true;
  Ready(a, kNow);
  Ready(b, kNow);
  Ready(c, kNow);
  a.engine.Put(MakeCookie(".example.com", "sid", "v"));
  a.Scan(kNow + 1000);
  Sync(b, a, kNow + 2000);
  Sync(c, b, kNow + 3000);  // C hears it only through B
  const auto& relayed = c.engine.cookies.begin()->second;
  assert(relayed["sameSite"] == "Lax");  // A's record, not B's normalised read-back
}

void TestRefusedWriteIsNotALocalChange() {
  Device a("a-refuse"), b("b-refuse");
  Ready(a, kNow);
  b.engine.Put(MakeCookie(".example.com", "sid", "old"));
  Ready(b, kNow);
  b.Scan(kNow + 10);
  b.engine.refuses_writes = true;
  a.engine.Put(MakeCookie(".example.com", "sid", "new"));
  a.Scan(kNow + 1000);
  Sync(b, a, kNow + 2000);
  assert(b.engine.ValueOf(".example.com", "sid") == "old");
  assert(b.Scan(kNow + 3000)["changed"] == 0);  // no competing record
  // B must not push its old value back to A.
  Sync(b, a, kNow + 4000);
  assert(a.engine.ValueOf(".example.com", "sid") == "new");
}

void TestReshapedWriteDoesNotLoop() {
  Device a("a-reshape"), b("b-reshape");
  b.engine.host_only_only = true;
  Ready(a, kNow);
  Ready(b, kNow);
  a.engine.Put(MakeCookie(".example.com", "sid", "v"));
  a.Scan(kNow + 1000);
  for (int round = 0; round < 3; ++round) {
    Sync(b, a, kNow + 2000 + round * 1000);
    b.Scan(kNow + 2500 + round * 1000);
    Sync(a, b, kNow + 2700 + round * 1000);
    a.Scan(kNow + 2800 + round * 1000);
  }
  assert(a.engine.Has(".example.com", "sid"));
  assert(!a.engine.Has("example.com", "sid"));  // B's variant never travels back
  assert(a.Scan(kNow + 9000)["changed"] == 0);
}

void TestConflictLastWriterWins() {
  Device a("a-lww"), b("b-lww");
  Ready(a, kNow);
  Ready(b, kNow);
  a.engine.Put(MakeCookie(".example.com", "sid", "from-a"));
  a.Scan(kNow + 1000);
  b.engine.Put(MakeCookie(".example.com", "sid", "from-b"));
  b.Scan(kNow + 2000);
  Sync(a, b, kNow + 3000);
  Sync(b, a, kNow + 3000);
  assert(a.engine.ValueOf(".example.com", "sid") == "from-b");
  assert(b.engine.ValueOf(".example.com", "sid") == "from-b");
}

void TestRestartRestoresSessionCookiesFromPeer() {
  Device a("a-restart"), b("b-restart");
  Ready(a, kNow);
  Ready(b, kNow);
  a.engine.Put(MakeCookie(".example.com", "session", "logged-in", std::nullopt));
  a.Scan(kNow + 1000);
  Sync(b, a, kNow + 2000);

  // A restarts: session cookie gone, and the site sets an anonymous one first.
  a.engine.Remove(".example.com", "session");
  a.Open(true, kNow + 10000);
  a.engine.Put(MakeCookie(".example.com", "session", "anonymous", std::nullopt));
  PullAll(a, b, kNow + 11000);  // warm-up merges B's snapshot
  a.store->FinishWarmup();
  a.Scan(kNow + 12000);
  assert(a.engine.ValueOf(".example.com", "session") == "logged-in");
  Sync(b, a, kNow + 13000);
  assert(b.engine.ValueOf(".example.com", "session") == "logged-in");
}

void TestDeletionReachesDeviceThatWasAway() {
  Device a("a-away"), b("b-away");
  Ready(a, kNow);
  Ready(b, kNow);
  a.engine.Put(MakeCookie(".example.com", "sid", "v"));
  a.Scan(kNow + 1000);
  Sync(b, a, kNow + 2000);
  // B goes away for over a year; A logs out meanwhile.
  a.engine.Remove(".example.com", "sid");
  a.Scan(kNow + 3000);
  const std::int64_t later = kNow + 86400000LL * 400;
  a.Open(true, later);
  a.store->FinishWarmup();
  a.Scan(later);
  b.Open(true, later);
  b.store->FinishWarmup();
  b.Scan(later);
  Sync(b, a, later + 1000);
  Sync(a, b, later + 2000);
  assert(!a.engine.Has(".example.com", "sid"));
  assert(!b.engine.Has(".example.com", "sid"));
}

void TestPaginationWithConcurrentChanges() {
  Device a("a-pages"), b("b-pages");
  Ready(a, kNow);
  Ready(b, kNow);
  for (int i = 0; i < 1200; ++i) a.engine.Put(MakeCookie(".s" + std::to_string(i % 200) + ".com", "c" + std::to_string(i), "v"));
  a.Scan(kNow + 1000);

  // First page only, then a change lands before the next page is requested.
  json since = b.store->Watermark(a.replica);
  json pull = {{"op", "pull"}, {"replica", b.replica}, {"since", since}, {"wait", 0}};
  json response = a.store->AnswerPull(pull, a.engine.Snapshot(), json{{"all", true}}, kNow + 2000);
  assert(response["records"].size() == kPageSize && response["more"] == true);
  b.store->CommitMerge(b.engine.Apply(b.store->PlanMerge(
      response["records"], json{{"replica", response["replica"]}, {"seq", response["seq"]}}, kNow + 2000)));
  a.engine.Put(MakeCookie(".late.com", "late", "v"));
  a.Scan(kNow + 2500);
  PullAll(b, a, kNow + 3000);
  assert(b.engine.cookies.size() == 1201);
}

void TestCapsKeepStoresBelowEngineLimits() {
  Device a("a-caps"), b("b-caps");
  Ready(a, kNow);
  Ready(b, kNow);
  for (int i = 0; i < 160; ++i) a.engine.Put(MakeCookie(".big.com", "c" + std::to_string(i), "v"));
  a.Scan(kNow + 1000);
  Sync(b, a, kNow + 2000);
  assert(b.engine.cookies.size() == kMaxCookiesPerHost);
  assert(b.store->Status()["skipped"] == 10);
}

void TestBusyDuringMerge() {
  Device a("a-busy"), b("b-busy");
  Ready(a, kNow);
  Ready(b, kNow);
  a.engine.Put(MakeCookie(".example.com", "sid", "v"));
  a.Scan(kNow + 1000);
  json pull = {{"op", "pull"}, {"replica", b.replica}, {"since", b.store->Watermark(a.replica)}, {"wait", 0}};
  json response = a.store->AnswerPull(pull, a.engine.Snapshot(), json{{"all", true}}, kNow + 2000);
  json plan = b.store->PlanMerge(response["records"], json{{"replica", a.replica}, {"seq", response["seq"]}}, kNow);
  bool threw = false;
  try {
    b.Scan(kNow + 2100);
  } catch (const SyncError& error) {
    threw = error.code == "BUSY";
  }
  assert(threw);
  // Watermark has not moved before commit.
  assert(b.store->Watermark(a.replica)["seq"] == 0);
  b.store->CommitMerge(b.engine.Apply(plan));
  assert(b.store->Watermark(a.replica)["seq"] == response["seq"]);
}

void TestWarmingPeerAnswersEmpty() {
  Device a("a-warm"), b("b-warm");
  Ready(a, kNow);
  b.Open(true, kNow);
  json pull = {{"op", "pull"}, {"replica", a.replica}, {"since", {{"replica", "x"}, {"seq", 0}}}, {"wait", 0}};
  json response = b.store->AnswerPull(pull, b.engine.Snapshot(), json{{"all", true}}, kNow);
  assert(response["warming"] == true && response["records"].empty());
}

}  // namespace

int main() {
  return RunGuarded([] {
    TestLoginAndLogoutPropagate();
    TestPushCarriesInitiatorChanges();
    TestEchoGuardWithNormalisingEngine();
    TestThirdDeviceGetsTheAcceptedRecord();
    TestRefusedWriteIsNotALocalChange();
    TestReshapedWriteDoesNotLoop();
    TestConflictLastWriterWins();
    TestRestartRestoresSessionCookiesFromPeer();
    TestDeletionReachesDeviceThatWasAway();
    TestPaginationWithConcurrentChanges();
    TestCapsKeepStoresBelowEngineLimits();
    TestBusyDuringMerge();
    TestWarmingPeerAnswersEmpty();
  });
}
