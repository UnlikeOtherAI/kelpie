// Real DNS-SD round trip on this machine. It needs working multicast, so it
// runs only with KELPIE_SYNC_MDNS_LIVE=1; otherwise it reports a skip.
// Optional: KELPIE_SYNC_MDNS_HOLD=<seconds> keeps the advertisement up so
// another machine can browse it (dns-sd -B _kelpie-sync._tcp).
#include "sync_discovery_windows.h"

#include <atomic>
#include <cassert>
#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <iostream>
#include <mutex>
#include <set>
#include <string>
#include <thread>

using namespace kelpie::windows;
using namespace std::chrono_literals;

namespace {

struct Seen {
  std::mutex mutex;
  std::condition_variable changed;
  std::set<std::string> present;
  std::set<std::string> lost;
  int port = 0;
  std::string id;
  std::string hint;
  std::size_t addresses = 0;
};

template <typename Predicate>
bool WaitFor(Seen& seen, std::chrono::seconds timeout, Predicate predicate) {
  std::unique_lock<std::mutex> lock(seen.mutex);
  return seen.changed.wait_for(lock, timeout, predicate);
}

}  // namespace

int main() {
  const char* live = std::getenv("KELPIE_SYNC_MDNS_LIVE");
  if (live == nullptr || std::string(live) != "1") {
    std::cout << "live mDNS round trip skipped (set KELPIE_SYNC_MDNS_LIVE=1)\n";
    return 0;
  }
  if (!SyncDiscoveryWindows::ApiAvailable()) {
    std::cerr << "DNS-SD API unavailable\n";
    return 1;
  }
  const std::string id = "liveTestReplica" + std::to_string(GetCurrentProcessId());
  const std::string instance = "kelpie-" + id;
  Seen seen;
  SyncDiscoveryWindows advertiser;
  SyncDiscoveryWindows browser;
  // The advertiser also browses: it must never report itself.
  std::atomic<bool> self_seen{false};
  assert(advertiser.Browse([&](const kelpie::SyncPeerAdvert& advert) {
                             if (advert.instance == instance) self_seen = true;
                           },
                           [](const std::string&) {}));
  assert(browser.Browse(
      [&](const kelpie::SyncPeerAdvert& advert) {
        std::lock_guard<std::mutex> lock(seen.mutex);
        if (advert.instance != instance) return;
        seen.present.insert(advert.instance);
        seen.port = advert.port;
        seen.id = advert.txt.count("id") ? advert.txt.at("id") : "";
        seen.hint = advert.txt.count("h") ? advert.txt.at("h") : "";
        seen.addresses = advert.addresses.size();
        seen.changed.notify_all();
      },
      [&](const std::string& lost) {
        std::lock_guard<std::mutex> lock(seen.mutex);
        seen.present.erase(lost);
        seen.lost.insert(lost);
        seen.changed.notify_all();
      }));
  assert(!advertiser.Advertise(0, {{"v", "1"}, {"id", id}}));
  assert(!advertiser.Advertise(43210, {{"v", "1"}}));
  assert(advertiser.Advertise(43210, {{"v", "1"}, {"id", id}, {"h", "aGludA"}}));

  if (!WaitFor(seen, 15s, [&] { return seen.present.count(instance) != 0; })) {
    std::cerr << "advertisement was not found by the browser\n";
    return 1;
  }
  {
    std::lock_guard<std::mutex> lock(seen.mutex);
    std::cout << "found port=" << seen.port << " addresses=" << seen.addresses << "\n";
    assert(seen.port == 43210 && seen.id == id && seen.addresses > 0);
  }

  // A TXT change is re-registered and seen with the new value.
  advertiser.UpdateTxt({{"v", "1"}, {"id", id}, {"h", "bmV3"}});
  if (!WaitFor(seen, 15s, [&] { return seen.present.count(instance) != 0 && seen.hint == "bmV3"; })) {
    std::cerr << "re-registered advertisement was not found\n";
    return 1;
  }

  if (const char* hold = std::getenv("KELPIE_SYNC_MDNS_HOLD")) {
    std::cout << "holding advertisement " << instance << " for " << hold << " s\n" << std::flush;
    std::this_thread::sleep_for(std::chrono::seconds(std::atoi(hold)));
  }

  advertiser.StopAdvertising();
  if (!WaitFor(seen, 15s, [&] { return seen.lost.count(instance) != 0; })) {
    std::cerr << "goodbye was not reported as lost\n";
    return 1;
  }
  assert(!self_seen);
  browser.StopBrowsing();
  advertiser.StopBrowsing();
  std::cout << "live mDNS round trip passed\n";
  return 0;
}
