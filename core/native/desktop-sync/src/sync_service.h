#pragma once

// DesktopCookieSync internals, shared by the lifecycle (sync_service.cpp),
// responder (sync_service_responder.cpp) and initiator
// (sync_service_initiator.cpp) files.
//
// Threads: the shell calls Tick/Status/Stop. A control thread owns the
// lifecycle and timers. The StoreHost executor owns the store. Listener
// workers run the responder. Each handshake attempt and each initiator
// session loop (pull, push) has its own thread.
//
// Locking: mu_ guards all service state. It is never held across network,
// UOA, discovery, cookie-store or executor calls, nor while joining threads.

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

#include "account_service.h"
#include "kelpie/desktop_sync.h"
#include "kelpie/sync_cookie_store.h"
#include "sync_listener.h"
#include "sync_protocol.h"
#include "sync_store_host.h"

namespace kelpie {

using desktop_sync::Clock;
using Json = nlohmann::json;

class DesktopCookieSync::Impl : public desktop_sync::SyncResponder {
 public:
  explicit Impl(Config config);
  ~Impl() override;

  void Tick();
  void Stop();
  Json Status() const;

  // SyncResponder (listener worker threads).
  desktop_sync::SyncReply Hello(const std::string& body, const std::string& source) override;
  desktop_sync::SyncReply Auth(const std::string& body) override;
  bool SessionLive(const std::string& session_id) override;
  desktop_sync::SyncReply Exchange(const std::string& session_id, const std::string& body) override;

 private:
  // One signed-in, opened store lifetime. Everything asynchronous captures it.
  struct Epoch {
    std::uint64_t id = 0;
    std::string subject;
    std::uint64_t account_generation = 0;
    std::string replica;
    bool launch = false;
    Clock::time_point opened;
    std::atomic<bool> cancelled{false};
  };
  using EpochRef = std::shared_ptr<Epoch>;

  struct Worker {
    std::thread thread;
    std::atomic<bool> done{false};
  };

  // An initiator session: one long-poll pull loop and one push loop.
  struct Outgoing {
    desktop_sync::EstablishedSession channel;
    EpochRef epoch;
    Clock::time_point expires;
    std::atomic<std::uint64_t> next_seq{1};
    desktop_sync::AbortSet aborts;
    std::atomic<bool> ended{false};
    std::string end_error;  // guarded by mu_
    // The responder's watermark of this replica (yourWatermark).
    std::optional<Json> watermark;  // guarded by mu_
    std::vector<std::shared_ptr<Worker>> workers;
  };

  struct Incoming {
    std::string id;
    desktop_sync::SessionKeys keys;
    std::string peer_replica;
    EpochRef epoch;
    Clock::time_point expires;
    std::mutex window_mutex;
    desktop_sync::ReplayWindow window;
  };

  struct Pending {
    std::string id;
    desktop_sync::HelloSide initiator, responder;
    std::unique_ptr<desktop_sync::EcdhKey> key;
    std::string challenge;
    EpochRef epoch;
    Clock::time_point expires;
  };

  struct Peer {
    std::string replica, instance;
    std::vector<std::string> addresses;
    int port = 0;
    bool advertised = false;
    Clock::time_point first_seen;
    bool in_warmup_window = false;
    bool warm_complete = false;
    std::string platform, name;
    bool handshaking = false;
    int failures = 0;
    Clock::time_point next_attempt{};
    std::string last_error;
    std::int64_t last_sync_at = 0;
    std::shared_ptr<Outgoing> outgoing;
    std::string incoming;  // responder session id
  };

  // Lifecycle (sync_service.cpp).
  void ControlLoop();
  void Reconcile(const account::AccountService::Identity& identity);
  void StartEpoch(const account::AccountService::Identity& identity);
  void StopEpoch();
  void RunTimers();
  void CheckWarmup(const EpochRef& epoch);
  void RefreshAdvertisement(const EpochRef& epoch);
  void ScheduleHandshakes(const EpochRef& epoch);
  void ExpireSessions();
  void ReapWorkers();
  std::map<std::string, std::string> Txt(const EpochRef& epoch, std::int64_t now) const;
  void OnFound(std::uint64_t epoch_id, const SyncPeerAdvert& advert);
  void OnLost(std::uint64_t epoch_id, const std::string& instance);
  void OnCookiesChanged();
  void OnHeadChanged();
  void Wake();
  void Fail(const std::string& reason, std::uint64_t generation);
  void Spawn(std::vector<std::shared_ptr<Worker>>* owner, std::function<void()> body);
  // Requires mu_. Used where a session must be registered and started atomically.
  static void SpawnLocked(std::vector<std::shared_ptr<Worker>>* owner, std::function<void()> body);
  void Log(const std::string& message) const;

  // Helpers shared by every file.
  bool Live(const EpochRef& epoch) const;
  desktop_sync::StoreHost::Cancelled CancelledFor(const EpochRef& epoch) const;
  std::int64_t Now() const;
  EpochRef CurrentEpoch() const;
  void MarkComplete(const EpochRef& epoch, const std::string& replica);

  // Responder (sync_service_responder.cpp).
  std::shared_ptr<Incoming> FindIncoming(const std::string& id) const;
  std::optional<Json> LongPoll(const Json& pull, const std::shared_ptr<Incoming>& session);
  std::optional<Json> AcceptPush(const Json& push, const std::shared_ptr<Incoming>& session);

  // Initiator (sync_service_initiator.cpp).
  void Handshake(EpochRef epoch, std::string replica);
  void InstallOutgoing(const EpochRef& epoch, const std::string& replica, desktop_sync::EstablishedSession channel);
  void PullLoop(std::shared_ptr<Outgoing> session);
  void PushLoop(std::shared_ptr<Outgoing> session);
  void EndOutgoing(const std::shared_ptr<Outgoing>& session, const std::string& error);
  bool SessionUsable(const std::shared_ptr<Outgoing>& session) const;
  void Backoff(Peer* peer, const std::string& error);

  Config config_;
  desktop_sync::UoaGate uoa_{2};
  std::unique_ptr<desktop_sync::StoreHost> store_;
  std::unique_ptr<desktop_sync::SyncListener> listener_;  // control thread only

  mutable std::mutex mu_;
  std::condition_variable wake_;
  std::condition_variable changed_;  // head moved, or teardown: wakes long-polls and push loops
  std::uint64_t change_counter_ = 0;
  bool woken_ = false;
  std::atomic<bool> stopping_{false};
  std::optional<account::AccountService::Identity> desired_;
  EpochRef epoch_;
  std::uint64_t epoch_counter_ = 0;
  bool opened_once_ = false;
  bool warm_done_ = false;
  std::string reason_;  // why sync is not running while signed in
  bool supported_ = true;
  Clock::time_point retry_at_{};
  std::optional<std::uint64_t> failed_generation_;
  int port_ = 0;
  std::string hint_date_;
  std::optional<Clock::time_point> scan_due_;
  std::optional<Clock::time_point> scan_first_signal_;
  std::map<std::string, Peer> peers_;  // by replica
  std::map<std::string, std::shared_ptr<Incoming>> incoming_;
  std::deque<std::unique_ptr<Pending>> pending_;
  std::deque<Clock::time_point> outgoing_attempts_;
  std::vector<std::shared_ptr<Worker>> workers_;  // handshake threads
  std::vector<std::shared_ptr<desktop_sync::AbortSet>> handshake_aborts_;
  std::thread control_;
};

}  // namespace kelpie
