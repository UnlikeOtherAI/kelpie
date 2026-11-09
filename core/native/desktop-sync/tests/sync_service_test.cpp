// End-to-end: DesktopCookieSync instances over real loopback HTTP with real
// crypto, a fake UOA, fake default cookie stores and an in-process mDNS.
// Proves login, logout and restart-restore propagate, that another account is
// refused, that /auth is single use and that the replay window holds.
#include <cassert>
#include <cstdio>
#include <limits>
#include <memory>

#include "base64url.h"
#include "kelpie/bookmark_store.h"
#include "protocol.h"
#include "sync_protocol.h"
#include "sync_test_support.h"

using namespace kelpie;
using namespace kelpie::sync_test;
using account::AccountService;

namespace {

struct Device {
  Device(FakeUoa* uoa, FakeBus* bus, std::string id, std::string token)
      : name(std::move(id)), token(std::move(token)), uoa(uoa), discovery(bus, name),
        profile(TempProfile(name)), account(std::make_unique<AccountService>(bookmarks, uoa->Transport())) {}
  ~Device() {
    StopSync();
    account.reset();
    std::error_code ignored;
    std::filesystem::remove_all(profile, ignored);
  }

  void SignIn() {
    account->CompleteSignIn({token, 3600, {}, {}}, account_generation);
    assert(account->State().signed_in);
  }
  void SignOut() {
    account->SignOut();
    ++account_generation;
  }
  void StartSync() {
    DesktopCookieSync::Config config;
    config.profile_dir = Utf8(profile);
    config.platform = "linux";
    config.device_name = "Device " + name;
    config.account = account.get();
    config.cookies = &cookies;
    config.discovery = &discovery;
    config.bind_address = "127.0.0.1";
    config.timings = FastTimings();
    sync = std::make_unique<DesktopCookieSync>(config);
    ticking = true;
    ticker = std::thread([this] {
      while (ticking) {
        sync->Tick();
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
      }
    });
  }
  void StopSync() {
    ticking = false;
    if (ticker.joinable()) ticker.join();
    sync.reset();
  }
  json Status() const { return sync->Status(); }
  // Sync is up and past warm-up.
  bool Running() const {
    const json status = Status();
    return status.value("supported", false) && status.contains("replica") && status["store"]["warming"] == false;
  }
  bool ConnectedTo(const std::string& replica) const {
    for (const auto& peer : Status().value("peers", json::array())) {
      if (peer["replica"] == replica && peer["state"] == "connected") return true;
    }
    return false;
  }
  std::string Replica() const { return Status().value("replica", std::string()); }

  std::string name, token;
  FakeUoa* uoa;
  FakeCookies cookies;
  FakeDiscovery discovery;
  std::filesystem::path profile;
  BookmarkStore bookmarks;
  std::unique_ptr<AccountService> account;
  std::uint64_t account_generation = 0;
  std::unique_ptr<DesktopCookieSync> sync;
  std::atomic<bool> ticking{false};
  std::thread ticker;
};

std::int64_t NowMillis() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count();
}

void Connect(Device& a, Device& b) {
  const bool connected = WaitFor([&] {
    return a.Running() && b.Running() && a.ConnectedTo(b.Replica()) && b.ConnectedTo(a.Replica());
  });
  if (!connected) std::fprintf(stderr, "A=%s\nB=%s\n", a.Status().dump().c_str(), b.Status().dump().c_str());
  assert(connected);
}

void LoginLogoutRestart(FakeUoa& uoa, FakeBus& bus) {
  Device a(&uoa, &bus, "a", "token-a"), b(&uoa, &bus, "b", "token-b");
  a.SignIn();
  b.SignIn();
  a.StartSync();
  b.StartSync();
  Connect(a, b);
  const json shape = a.Status();
  assert(shape["supported"] == true && shape["signedIn"] == true && shape["listening"] == true);
  assert(shape["peers"].size() == 1 && shape["peers"][0]["platform"] == "linux" && shape["peers"][0]["name"] == "Device b");
  for (const char* key : {"entries", "tombstones", "localOnly", "unapplied", "skipped", "warming", "lastPurgeAt"}) {
    assert(shape["store"].contains(key));
  }
  assert(uoa.pairs >= 2 && uoa.validations >= 2);

  // Login on A reaches B with every attribute; a host-only cookie on B reaches A.
  a.cookies.Put(".example.com", "sid", "alice-1");
  b.cookies.Put("b.example.org", "pref", "dark");
  assert(WaitFor([&] { return b.cookies.Value(".example.com", "sid") == std::optional<std::string>("alice-1"); }));
  assert(WaitFor([&] { return a.cookies.Value("b.example.org", "pref") == std::optional<std::string>("dark"); }));
  const json copied = b.cookies.Get(".example.com", "sid");
  assert(copied["httpOnly"] == true && copied["secure"] == true && copied["sameSite"] == "Lax" &&
         copied["expires"] == 4102444800);

  // A change on B is accepted back on A.
  b.cookies.Put(".example.com", "sid", "alice-2");
  assert(WaitFor([&] { return a.cookies.Value(".example.com", "sid") == std::optional<std::string>("alice-2"); }));

  // Logout of a site on A removes the cookie on B.
  a.cookies.Remove(".example.com", "sid");
  assert(WaitFor([&] { return !b.cookies.Value(".example.com", "sid"); }));

  // A session cookie from B reaches A, then A restarts and loses it.
  b.cookies.Put(".example.com", "sess", "keep-me", std::nullopt);
  assert(WaitFor([&] { return a.cookies.Value(".example.com", "sess").has_value(); }));
  const std::string old_replica = a.Replica();
  a.StopSync();
  a.cookies.DropSessionCookies();
  assert(!a.cookies.Value(".example.com", "sess"));
  a.StartSync();
  // The restart is the first open of this instance: warm-up, then the peers' session cookies return.
  assert(WaitFor([&] { return a.Replica() != "" && a.Replica() != old_replica; }));
  assert(WaitFor([&] { return a.cookies.Value(".example.com", "sess") == std::optional<std::string>("keep-me"); }));
  assert(WaitFor([&] { return a.Running(); }));
  Connect(a, b);
  std::this_thread::sleep_for(std::chrono::milliseconds(600));
  // The restart did not look like a logout anywhere.
  assert(b.cookies.Value(".example.com", "sess") == std::optional<std::string>("keep-me"));
  assert(b.cookies.Value("b.example.org", "pref") == std::optional<std::string>("dark"));
  assert(a.cookies.Value("b.example.org", "pref") == std::optional<std::string>("dark"));
  assert(!a.cookies.Value(".example.com", "sid") && !b.cookies.Value(".example.com", "sid"));

  // Sign-out stops sync; a cookie set meanwhile arrives after the next sign-in,
  // which starts without warm-up because it is not the first open.
  a.SignOut();
  assert(WaitFor([&] {
    const json status = a.Status();
    return status["signedIn"] == false && status["supported"] == false && status["reason"] == "signed-out" &&
           !status.contains("replica") && status["listening"] == false;
  }));
  b.cookies.Put(".example.com", "later", "while-away");
  std::this_thread::sleep_for(std::chrono::milliseconds(300));
  assert(!a.cookies.Value(".example.com", "later"));
  a.SignIn();
  assert(WaitFor([&] { return a.Replica() != ""; }));
  assert(a.Status()["store"]["warming"] == false);  // not the first open: no warm-up
  assert(WaitFor([&] { return a.cookies.Value(".example.com", "later") == std::optional<std::string>("while-away"); }));
}

void OtherAccountRefused(FakeUoa& uoa, FakeBus& bus) {
  Device a(&uoa, &bus, "alice", "token-alice"), bob(&uoa, &bus, "bob", "token-bob");
  Device spare(&uoa, &bus, "spare", "token-spare");  // a second Alice account session, no sync running
  a.SignIn();
  bob.SignIn();
  spare.SignIn();
  a.StartSync();
  bob.StartSync();
  assert(WaitFor([&] { return a.Running() && bob.Running(); }));
  bob.cookies.Put(".example.com", "sid", "bob-session");
  std::this_thread::sleep_for(std::chrono::milliseconds(1500));
  // Different hints: the adverts are ignored, nothing is exchanged.
  assert(!a.cookies.Value(".example.com", "sid"));
  assert(a.Status()["peers"].empty() && bob.Status()["peers"].empty());

  const json status = a.Status();
  const int port = a.discovery.port();
  const std::string replica = status["replica"];
  desktop_sync::UoaGate gate(2);
  desktop_sync::AbortSet aborts;
  const auto attempt = [&](AccountService& account, const std::string& subject, const std::string& own,
                           std::function<std::int64_t()> clock) {
    desktop_sync::InitiatorRequest request;
    request.account = &account;
    request.generation = account.Generation();
    request.replica = own;
    request.platform = "linux";
    request.name = "test";
    request.hint = sync::AccountHint(subject, NowMillis());
    request.addresses = {"127.0.0.1"};
    request.port = port;
    request.expected_replica = replica;
    request.now_millis = std::move(clock);
    request.live = [] { return true; };
    request.gate = &gate;
    request.aborts = &aborts;
    return desktop_sync::RunInitiatorHandshake(request);
  };
  // Bob forging Alice's public hint passes discovery but fails the UOA proof.
  const auto forged = attempt(*bob.account, "alice", desktop_sync::RandomToken(16), NowMillis);
  assert(!forged.session && forged.error == "AUTH_FAILED");
  // Bob's own hint is refused before any UOA call.
  const int before = uoa.validations;
  const auto mismatch = attempt(*bob.account, "bob", desktop_sync::RandomToken(16), NowMillis);
  assert(!mismatch.session && mismatch.error == "ACCOUNT_MISMATCH" && uoa.validations == before);
  // A clock more than two minutes off is refused at hello.
  const auto skewed = attempt(*spare.account, "alice", desktop_sync::RandomToken(16),
                              [] { return NowMillis() + 3 * 60 * 1000; });
  assert(!skewed.session && skewed.error == "CLOCK_SKEW");

  // /auth is single use: the first consumes the handshake whatever the outcome.
  desktop_sync::SyncClient client(*desktop_sync::ParseIp("127.0.0.1"), port);
  const auto key = desktop_sync::EcdhKey::Generate();
  const json hello = {{"v", 1}, {"replica", desktop_sync::RandomToken(16)}, {"hint", sync::AccountHint("alice", NowMillis())},
                      {"now", NowMillis()}, {"platform", "linux"}, {"name", "raw"},
                      {"key", sync::Base64UrlEncode(key->PublicKey().data(), key->PublicKey().size())},
                      {"nonce", desktop_sync::RandomToken(32)}};
  const auto reply = client.Post(desktop_sync::kHelloPath, hello, std::chrono::seconds(5));
  assert(reply.status == 200 && reply.body.contains("handshakeId"));
  const json auth = {{"handshakeId", reply.body["handshakeId"]}, {"ticket", "not-a-ticket"}};
  const auto first = client.Post(desktop_sync::kAuthPath, auth, std::chrono::seconds(5));
  assert(first.status == 403 && first.body["error"] == "AUTH_FAILED");
  const auto replay = client.Post(desktop_sync::kAuthPath, auth, std::chrono::seconds(5));
  assert(replay.status == 401 && replay.body["error"] == "SYNC_SESSION");

  // Clocks at the ends of int64 are refused as skew, never overflowing.
  for (const std::int64_t extreme : {std::numeric_limits<std::int64_t>::min(), std::numeric_limits<std::int64_t>::max()}) {
    json skew = hello;
    skew["replica"] = desktop_sync::RandomToken(16);
    skew["now"] = extreme;
    const auto refused = client.Post(desktop_sync::kHelloPath, skew, std::chrono::seconds(5));
    assert(refused.status == 409 && refused.body["error"] == "CLOCK_SKEW");
  }
  // No unproven hello (forged, mismatched, skewed or failed /auth) became a peer.
  assert(a.Status()["peers"].empty());

  // A genuine second Alice session is admitted; its sequence numbers are replay-checked.
  const std::string own = desktop_sync::RandomToken(16);
  const auto genuine = attempt(*spare.account, "alice", own, NowMillis);
  assert(genuine.session && genuine.error.empty() && genuine.session->peer_replica == replica);
  // Proof succeeded: now, and only now, the initiator is a peer, with its hello identity.
  const json peers = a.Status()["peers"];
  assert(peers.size() == 1 && peers[0]["replica"] == own && peers[0]["platform"] == "linux" &&
         peers[0]["name"] == "test" && peers[0]["state"] == "connected");
  desktop_sync::SyncClient channel(genuine.session->target, genuine.session->port);
  const auto exchange = [&](std::uint64_t seq, const std::string& as) {
    const json pull = {{"op", "pull"}, {"replica", as}, {"since", {{"replica", replica}, {"seq", 0}}}, {"wait", 0}};
    return desktop_sync::InitiatorExchange(*genuine.session, channel, seq, pull, std::chrono::seconds(5));
  };
  const auto answered = exchange(5, own);
  assert(answered.plaintext && (*answered.plaintext)["replica"] == replica);
  assert(exchange(5, own).error == "REPLAY");
  assert(exchange(70, own).plaintext);
  assert(exchange(5, own).error == "REPLAY");   // 65 below the highest
  assert(exchange(6, own).plaintext);           // 64 below and unseen
  assert(exchange(6, own).error == "REPLAY");
  // The inner message is bound to the session's initiator replica.
  assert(exchange(71, desktop_sync::RandomToken(16)).error == "INVALID_MESSAGE");
  // A box sealed with the wrong key or for another seq is refused without burning the seq.
  {
    auto wrong = *genuine.session;
    wrong.keys.i2r[0] ^= 1;
    const json pull = {{"op", "pull"}, {"replica", own}, {"since", {{"replica", replica}, {"seq", 0}}}, {"wait", 0}};
    assert(desktop_sync::InitiatorExchange(wrong, channel, 80, pull, std::chrono::seconds(5)).error == "INVALID_BOX");
    assert(exchange(80, own).plaintext);
  }
  // Signing out tears the session down.
  a.SignOut();
  assert(WaitFor([&] { return a.Status().value("reason", std::string()) == "signed-out"; }));
  const std::string after = exchange(81, own).error;
  assert(after == "UNREACHABLE" || after == "SYNC_SESSION");
}

// A LAN peer rotating replicas with a valid (public) hint cannot grow state:
// unproven hellos live only in the 8-entry pending table and never in peers.
void HelloFlood(FakeUoa& uoa, FakeBus& bus) {
  Device a(&uoa, &bus, "flooded", "token-flooded");
  a.SignIn();
  a.StartSync();
  assert(WaitFor([&] { return a.Running(); }));
  desktop_sync::SyncClient client(*desktop_sync::ParseIp("127.0.0.1"), a.discovery.port());
  std::vector<std::string> handshakes;
  for (int i = 0; i < 9; ++i) {  // under the 10-a-minute hello rate limit
    const auto key = desktop_sync::EcdhKey::Generate();
    const json hello = {{"v", 1}, {"replica", desktop_sync::RandomToken(16)},
                        {"hint", sync::AccountHint("alice", NowMillis())}, {"now", NowMillis()},
                        {"platform", "linux"}, {"name", "flood"},
                        {"key", sync::Base64UrlEncode(key->PublicKey().data(), key->PublicKey().size())},
                        {"nonce", desktop_sync::RandomToken(32)}};
    const auto reply = client.Post(desktop_sync::kHelloPath, hello, std::chrono::seconds(5));
    assert(reply.status == 200);
    handshakes.push_back(reply.body["handshakeId"]);
  }
  assert(a.Status()["peers"].empty());
  // The ninth hello evicted the first pending handshake.
  const auto evicted = client.Post(desktop_sync::kAuthPath, {{"handshakeId", handshakes.front()}, {"ticket", "t"}},
                                   std::chrono::seconds(5));
  assert(evicted.status == 401 && evicted.body["error"] == "SYNC_SESSION");
  const auto newest = client.Post(desktop_sync::kAuthPath, {{"handshakeId", handshakes.back()}, {"ticket", "t"}},
                                  std::chrono::seconds(5));
  assert(newest.status == 403 && newest.body["error"] == "AUTH_FAILED");
  assert(a.Status()["peers"].empty());
}

void Unsupported(FakeUoa& uoa, FakeBus&) {
  // Without discovery the service reports why and never listens.
  BookmarkStore bookmarks;
  AccountService account(bookmarks, uoa.Transport());
  account.CompleteSignIn({"token-unsupported", 3600, {}, {}}, 0);
  FakeCookies cookies;
  DesktopCookieSync::Config config;
  config.profile_dir = Utf8(TempProfile("unsupported"));
  config.platform = "windows";
  config.account = &account;
  config.cookies = &cookies;
  DesktopCookieSync sync(config);
  sync.Tick();
  assert(WaitFor([&] { return sync.Status().value("reason", std::string()) == "mdns-unavailable"; }));
  assert(sync.Status()["supported"] == false && !sync.Status().contains("replica") && sync.Status()["listening"] == false);
  sync.Stop();
  std::filesystem::remove_all(std::filesystem::path(std::u8string(config.profile_dir.begin(), config.profile_dir.end())));
}

}  // namespace

int main() {
  FakeUoa uoa;
  uoa.subjects = {{"token-a", "alice"}, {"token-b", "alice"}, {"token-alice", "alice"}, {"token-spare", "alice"}, {"token-flooded", "alice"},
                  {"token-bob", "bob"}, {"token-unsupported", "carol"}};
  FakeBus bus;
  LoginLogoutRestart(uoa, bus);
  std::puts("login, logout, restart-restore and re-sign-in propagate");
  FakeBus other_bus;
  OtherAccountRefused(uoa, other_bus);
  std::puts("another account, a forged hint, clock skew and replays are refused");
  FakeBus flood_bus;
  HelloFlood(uoa, flood_bus);
  std::puts("a replica-rotating hello flood stays bounded");
  Unsupported(uoa, bus);
  std::puts("sync_service_test passed");
  return 0;
}
