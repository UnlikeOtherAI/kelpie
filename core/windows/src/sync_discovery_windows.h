#pragma once

// `_kelpie-sync._tcp` advertising and browsing through the Windows 10 1809+
// DNS-SD API (DnsServiceRegister, DnsServiceBrowse, DnsServiceResolve). The
// functions are looked up at runtime, so Windows builds without them (older
// releases, Wine) still start and simply report mDNS as unavailable.
//
// Threading: every public method may be called from any thread except a
// found/lost callback's own destructor path. found/lost run one at a time on
// this object's worker thread, never on a DNS callback thread and never under
// this object's lock, so they may call back into it. After StopBrowsing()
// returns no new callback starts; one that is already running may finish.
// The automation API's `_kelpie._tcp` is never advertised from here.

#include <memory>
#include <string>

#include "sync_contract_pending.h"

namespace kelpie::windows {

class SyncDiscoveryWindows final : public SyncDiscovery {
 public:
  SyncDiscoveryWindows();
  ~SyncDiscoveryWindows() override;
  SyncDiscoveryWindows(const SyncDiscoveryWindows&) = delete;
  SyncDiscoveryWindows& operator=(const SyncDiscoveryWindows&) = delete;

  // False when the DNS-SD API is missing, `port` is invalid or `txt` has no
  // usable `id`. A registration the OS rejects later is retried with backoff.
  bool Advertise(int port, const std::map<std::string, std::string>& txt) override;
  // Re-registers with the new record; a changed `id` also renames the instance.
  void UpdateTxt(const std::map<std::string, std::string>& txt) override;
  // Sends the goodbye. Waits at most a few seconds for the OS to confirm.
  void StopAdvertising() override;
  bool Browse(std::function<void(const SyncPeerAdvert&)> found,
              std::function<void(const std::string& instance)> lost) override;
  void StopBrowsing() override;

  static bool ApiAvailable();

  struct State;  // Implementation detail, shared with the DNS callbacks.

 private:
  std::shared_ptr<State> state_;
};

}  // namespace kelpie::windows
