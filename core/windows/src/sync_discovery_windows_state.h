#pragma once

// Shared state of SyncDiscoveryWindows: advertising lives in
// sync_advertise_windows.cpp, browsing in sync_discovery_windows.cpp.

#include <chrono>
#include <condition_variable>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

#include "dnssd_browse_cache.h"
#include "dnssd_windows.h"
#include "sync_discovery_windows.h"
#include "kelpie/sync_peer_events.h"

namespace kelpie::windows {

struct SyncDiscoveryWindows::State : std::enable_shared_from_this<State> {
  using Clock = std::chrono::steady_clock;
  static constexpr wchar_t kBrowseName[] = L"_kelpie-sync._tcp.local";
  static constexpr char kServiceDomain[] = "_kelpie-sync._tcp.local";
  // Windows does not re-deliver a browse on its own; restarting it refreshes
  // TXT records (the account hint changes daily) and record TTLs.
  static constexpr auto kRefreshInterval = std::chrono::minutes(5);
  static constexpr auto kStopWait = std::chrono::seconds(3);
  static constexpr auto kRetryFirst = std::chrono::seconds(5);
  static constexpr auto kRetryMax = std::chrono::minutes(5);

  enum class Phase { kRegistering, kRegistered, kFailed, kDeregistering, kDone };
  struct Registration {
    std::uint64_t id = 0;
    DNS_SERVICE_REGISTER_REQUEST request{};
    PDNS_SERVICE_INSTANCE instance = nullptr;
    std::wstring host;
    std::wstring full_name;
    Phase phase = Phase::kRegistering;
    // Nobody waits any more: the final callback withdraws and frees it.
    bool orphaned = false;
    ~Registration() {
      if (instance != nullptr) dnssd::Api().free_instance(instance);
    }
  };
  struct Advert {
    int port = 0;
    SyncTxt txt;
  };
  struct Resolve {
    std::uint64_t id = 0;
    std::wstring name;
    DNS_SERVICE_CANCEL cancel{};
  };

  // Guarded by queue_mutex; the facade takes it out (and joins it) on destruction.
  std::mutex queue_mutex;
  std::unique_ptr<SyncSerialQueue> queue = std::make_unique<SyncSerialQueue>();
  SyncPeerDelivery delivery{[this](std::function<void()> task) { PostAt(Clock::now(), std::move(task)); }};

  std::mutex mutex;
  std::condition_variable settled;
  std::optional<Advert> wanted;
  std::map<std::uint64_t, std::unique_ptr<Registration>> registrations;
  std::uint64_t current = 0;
  std::chrono::seconds retry_delay{0};
  std::uint64_t retry_token = 0;

  std::uint64_t browse_generation = 0;  // 0: not browsing
  std::uint64_t browse_id = 0;
  DNS_SERVICE_CANCEL browse_cancel{};
  std::uint64_t refresh_token = 0;
  DnsSdBrowseCache cache{kServiceDomain};
  SyncPeerTable table;
  std::map<std::string, Resolve> resolves;  // by lower-case full name

  ~State();

  void PostAt(Clock::time_point when, std::function<void()> task);
  std::unique_ptr<SyncSerialQueue> TakeQueue();
  bool StartRegistration(const Advert& advert);
  void Retire(std::uint64_t id);
  void RetireCurrent();
  void OnRegistered(std::uint64_t id, DWORD status);
  void ScheduleRetry(std::uint64_t id);

  bool StartBrowse();
  void CancelBrowse();
  void ScheduleRefresh();
  void OnBrowse(std::uint64_t id, DWORD status, std::vector<DnsSdRecord> records);
  void OnResolved(std::uint64_t id, const std::string& key, PDNS_SERVICE_INSTANCE instance);
  void Publish(const DnsSdBrowseCache::Result& result);
  void StartResolve(const std::string& key);
  void CancelResolves();
};

}  // namespace kelpie::windows
