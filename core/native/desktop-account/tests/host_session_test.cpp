#include "account_service.h"
#include <atomic>
#include <cassert>
#include <condition_variable>
#include <thread>

using namespace kelpie::account;
namespace {
struct TrackingStore final : AccountSessionStore {
  int reads = 0, writes = 0, clears = 0;
  std::optional<AccountSession> Load() override { ++reads; return std::nullopt; }
  bool Save(const AccountSession&) override { ++writes; return true; }
  void Clear() override { ++clears; }
};
struct Host {
  std::mutex mutex;
  HostSessionState state{"person", "session-1"};
  bool wrong_identity = false;
  int sign_ins = 0, sign_outs = 0;
  std::function<void()> before_write;
  std::shared_ptr<HostSession> provider() {
    auto value = std::make_shared<HostSession>();
    value->state = [this] { std::lock_guard lock(mutex); return state; };
    value->request = [this](const auto& path, const auto& method, const auto&, const auto&) {
      if (path == "/oauth/me") return AccountResponse{
          wrong_identity ? R"({"sub":"other","email":"other@example.test"})" :
                           R"({"sub":"person","email":"person@example.test"})", {}};
      if (path == "/oauth/me/avatar") throw AccountFailure(404);
      assert(path == kAccountBookmarks);
      if (method == "PUT" && before_write) before_write();
      return AccountResponse{R"({"value":[]})", "version-1"};
    };
    value->sign_in = [this] { ++sign_ins; };
    value->sign_out = [this] { ++sign_outs; std::lock_guard lock(mutex); state = {}; };
    return value;
  }
};
void Ready(AccountService& account, bool expected = true) {
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(3);
  do {
    account.Poll();
    const auto state = account.State();
    if (state.signed_in || !state.error.empty()) { assert(state.signed_in == expected); return; }
    std::this_thread::yield();
  } while (std::chrono::steady_clock::now() < deadline);
  assert(false && "Host session did not settle");
}
void HostOwnsCredentials() {
  kelpie::BookmarkStore local;
  auto storage = std::make_shared<TrackingStore>();
  AccountService account(local, {}, storage);
  Host host;
  account.UseHostSession(host.provider());
  account.RestoreSession();
  Ready(account);
  account.Poll();
  assert(account.State().email == "person@example.test");
  account.SignOut();
  assert(!account.State().signed_in && host.sign_outs == 1);
  account.StartSignIn({}, [](const auto&) { assert(false); return false; });
  assert(host.sign_ins == 1);
  assert(storage->reads == 0 && storage->writes == 0 && storage->clears == 0);
}
void WrongIdentityIsRejected() {
  kelpie::BookmarkStore local;
  auto storage = std::make_shared<TrackingStore>();
  AccountService account(local, {}, storage);
  Host host; host.wrong_identity = true;
  account.UseHostSession(host.provider());
  Ready(account, false);
  assert(account.State().email.empty());
  assert(storage->reads == 0 && storage->writes == 0 && storage->clears == 0);
}
void ReplacedSessionFencesInflightWrites() {
  kelpie::BookmarkStore local;
  AccountService account(local);
  Host host;
  account.UseHostSession(host.provider());
  Ready(account);
  std::mutex mutex;
  std::condition_variable changed;
  bool blocked = false, released = false;
  host.before_write = [&] {
    std::unique_lock lock(mutex);
    blocked = true; changed.notify_all();
    changed.wait(lock, [&] { return released; });
  };
  auto action = std::async(std::launch::async, [&] {
    return account.BookmarkAction("add", {{"url", "https://example.test"}, {"title", "Example"}});
  });
  { std::unique_lock lock(mutex); changed.wait(lock, [&] { return blocked; }); }
  { std::lock_guard lock(host.mutex); host.state.epoch = "session-2"; }
  { std::lock_guard lock(mutex); released = true; changed.notify_all(); }
  assert(!action.get().at("success").get<bool>());
  assert(local.Count() == 0);
}
}
int main() {
  HostOwnsCredentials();
  WrongIdentityIsRejected();
  ReplacedSessionFencesInflightWrites();
}
