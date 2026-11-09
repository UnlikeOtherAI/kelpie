// Built without the Avahi headers (the no-CEF fallback on a system without
// libavahi-client-dev): sync reports mdns-unavailable.
#include "avahi_sync_discovery.h"

namespace kelpie::linuxapp {

struct AvahiSyncDiscovery::State {};

AvahiSyncDiscovery::AvahiSyncDiscovery() = default;
AvahiSyncDiscovery::~AvahiSyncDiscovery() = default;
bool AvahiSyncDiscovery::LibraryAvailable() { return false; }
bool AvahiSyncDiscovery::Advertise(int, const std::map<std::string, std::string>&) { return false; }
void AvahiSyncDiscovery::UpdateTxt(const std::map<std::string, std::string>&) {}
void AvahiSyncDiscovery::StopAdvertising() {}
bool AvahiSyncDiscovery::Browse(std::function<void(const SyncPeerAdvert&)>, std::function<void(const std::string&)>) {
  return false;
}
void AvahiSyncDiscovery::StopBrowsing() {}

}  // namespace kelpie::linuxapp
