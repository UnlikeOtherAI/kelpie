#pragma once

// `_kelpie-sync._tcp` advertising and browsing through the Avahi daemon.
//
// libavahi-client.so.3 and libavahi-common.so.3 are loaded with dlopen, so
// Kelpie starts on systems without Avahi (minimal installs, containers, an
// AppImage on a distribution without it). Without the libraries or a running
// daemon, Advertise() and Browse() return false and sync reports
// mdns-unavailable. A daemon that restarts later is reconnected to and the
// advertisement and browse are restored.
//
// Threading: public methods may be called from any thread except Avahi's own
// poll thread. found/lost run one at a time on this object's worker thread,
// never under the Avahi lock, so they may call back into this object. When
// StopBrowsing() returns no callback is running or will start: it waits for
// one in progress (so its caller must not hold a lock that callback takes),
// except when it is called from inside that callback. Never destroy the
// object from inside a callback. The automation API's `_kelpie._tcp` is never
// advertised from here.

#include <map>
#include <memory>
#include <string>

#include "sync_contract_pending.h"

namespace kelpie::linuxapp {

class AvahiSyncDiscovery final : public SyncDiscovery {
 public:
  AvahiSyncDiscovery();
  ~AvahiSyncDiscovery() override;
  AvahiSyncDiscovery(const AvahiSyncDiscovery&) = delete;
  AvahiSyncDiscovery& operator=(const AvahiSyncDiscovery&) = delete;

  bool Advertise(int port, const std::map<std::string, std::string>& txt) override;
  void UpdateTxt(const std::map<std::string, std::string>& txt) override;
  void StopAdvertising() override;
  bool Browse(std::function<void(const SyncPeerAdvert&)> found,
              std::function<void(const std::string& instance)> lost) override;
  void StopBrowsing() override;

  // Whether both Avahi libraries could be loaded. Says nothing about the daemon.
  static bool LibraryAvailable();

  struct State;  // Implementation detail, shared with the Avahi callbacks.

 private:
  std::unique_ptr<State> state_;
};

}  // namespace kelpie::linuxapp
