#pragma once

// Peer-to-peer cookie sync for the Windows and Linux desktop apps. See
// docs/plans/2026-11-09-p2p-cookie-sync.md ("Windows and Linux").
//
// One DesktopCookieSync per process. It opens the core-sync store on sign-in,
// runs a sync-only LAN listener (never the automation API), advertises and
// browses `_kelpie-sync._tcp` through the platform's SyncDiscovery, and stops
// everything on sign-out or account change. Embedded (host session) browsers
// report sync as unsupported.

#include <chrono>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

namespace kelpie {

namespace account {
class AccountService;
}
using account::AccountService;

struct SyncPeerAdvert {
  std::string instance;
  // Numeric addresses as resolved, e.g. "192.168.1.20", "fe80::1%12".
  std::vector<std::string> addresses;
  int port = 0;
  std::map<std::string, std::string> txt;
};

class SyncDiscovery {  // implemented per OS by the platform agent
 public:
  virtual ~SyncDiscovery() = default;
  virtual bool Advertise(int port, const std::map<std::string, std::string>& txt) = 0;  // _kelpie-sync._tcp
  virtual void UpdateTxt(const std::map<std::string, std::string>& txt) = 0;
  virtual void StopAdvertising() = 0;
  // Callbacks may run on any thread; they must not be called after StopBrowsing returns.
  virtual bool Browse(std::function<void(const SyncPeerAdvert&)> found,
                      std::function<void(const std::string& instance)> lost) = 0;
  virtual void StopBrowsing() = 0;
};

class SyncCookieStore;  // kelpie/sync_cookie_store.h; the CEF adapter implements it

class DesktopCookieSync {
 public:
  // Protocol timings. Tests shorten them; production uses the defaults.
  struct Timings {
    std::chrono::milliseconds warmup_window{15000};      // peers seen in this window gate warm-up
    std::chrono::milliseconds warmup_limit{30000};       // warm-up ends at the latest here
    std::chrono::milliseconds initiator_fallback{15000};  // the larger replica waits this long
    std::chrono::milliseconds session_lifetime{600000};  // 10 minutes
    std::chrono::milliseconds scan_quiet{1000};          // debounce after a change signal
    std::chrono::milliseconds pull_wait{25000};          // long-poll wait sent in pulls
    std::chrono::milliseconds backoff_min{5000};
    std::chrono::milliseconds backoff_max{300000};
  };

  struct Config {
    std::string profile_dir;
    std::string platform;      // "windows" | "linux"
    std::string device_name;
    AccountService* account = nullptr;
    SyncCookieStore* cookies = nullptr;
    SyncDiscovery* discovery = nullptr;  // nullptr → status reason "mdns-unavailable"
    // Listener bind address. Empty binds every interface (dual-stack where
    // available); the address rule still admits only eligible peers.
    std::string bind_address;
    // Wall clock in Unix milliseconds; defaults to the system clock.
    std::function<std::int64_t()> now_millis;
    // Content-free diagnostics (states and error codes only), never cookie
    // names, domains, values, tickets, keys or boxes. Optional.
    std::function<void(const std::string&)> log;
    Timings timings;
  };

  explicit DesktopCookieSync(Config config);
  ~DesktopCookieSync();
  DesktopCookieSync(const DesktopCookieSync&) = delete;
  DesktopCookieSync& operator=(const DesktopCookieSync&) = delete;

  void Tick();                   // call from the shell loop; drives sign-in/out detection
  void Stop();
  nlohmann::json Status() const; // the get-cookie-sync-status payload

  class Impl;

 private:
  std::unique_ptr<Impl> impl_;
};

}  // namespace kelpie
