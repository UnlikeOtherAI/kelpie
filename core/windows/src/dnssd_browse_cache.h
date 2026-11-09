#pragma once

// Turns Windows DNS-SD browse results into peer views. A browse callback
// carries one response: the PTR for the instance plus, usually, its SRV, TXT
// and A/AAAA records. Windows answers once per interface, so addresses are
// accumulated per host. A PTR with TTL 0 is a goodbye. Records are kept for
// their TTL; there is no OS cache to read back. Pure data, no Windows API.

#include <chrono>
#include <cstdint>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <vector>

#include "sync_peer_events.h"

namespace kelpie::windows {

struct DnsSdRecord {
  enum class Type { kPtr, kSrv, kTxt, kAddress };
  Type type = Type::kPtr;
  std::string name;  // owner name as received
  std::uint32_t ttl = 0;
  std::string target;  // PTR: instance full name; SRV: host name
  int port = 0;        // SRV
  std::vector<std::string> txt;
  std::string address;  // A/AAAA, numeric
};

class DnsSdBrowseCache {
 public:
  using Clock = std::chrono::steady_clock;

  struct Change {
    std::string instance;               // instance label, without the service suffix
    std::optional<SyncPeerView> view;   // nullopt: the instance is gone
  };
  struct Result {
    std::vector<Change> changes;
    std::vector<std::string> resolve;   // full names still missing SRV, TXT or an address
  };

  // `service` is the browse name, for example "_kelpie-sync._tcp.local".
  explicit DnsSdBrowseCache(std::string service);

  // This process's own advertisement; it is never reported.
  void SetOwnInstance(const std::string& full_name);
  Result Apply(const std::vector<DnsSdRecord>& records, Clock::time_point now);
  // A DnsServiceResolve answer, used when a browse response lacked records.
  Result Resolved(const std::string& full_name, const std::string& host, int port,
                  const std::vector<std::string>& txt, const std::vector<std::string>& addresses,
                  Clock::time_point now);
  Result Expire(Clock::time_point now);
  std::optional<Clock::time_point> NextExpiry() const;
  void Clear();

  // An address stays usable at least this long after it was last seen, so a
  // short host-record TTL cannot make a live peer flap between refreshes.
  static constexpr std::chrono::minutes kMinAddressLifetime{15};

 private:
  struct Instance {
    std::string label;
    Clock::time_point expires;
    std::string host;  // lower-case
    int port = 0;
    std::optional<SyncTxt> txt;
    std::map<std::string, Clock::time_point> resolved_addresses;
  };

  std::optional<std::string> InstanceKey(const std::string& full_name) const;
  std::string Label(const std::string& full_name) const;
  SyncPeerView View(const Instance& instance, Clock::time_point now) const;
  // Reports every touched instance that is still cached.
  void Collect(const std::set<std::string>& touched, Clock::time_point now, Result* result) const;
  void Erase(const std::string& key, Result* result);

  std::string service_;  // lower-case
  std::string own_;      // lower-case full name
  std::map<std::string, Instance> instances_;  // by lower-case full name
  std::map<std::string, std::map<std::string, Clock::time_point>> hosts_;  // host -> address -> expiry
};

}  // namespace kelpie::windows
