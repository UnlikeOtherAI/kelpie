// Discovery rules that do not need Avahi: TXT encoding, instance names, the
// per-instance merge and serial delivery, plus argument checks that must
// fail before Avahi is touched.
#include "avahi_sync_discovery.h"
#include "sync_peer_events.h"

#include <atomic>
#include <cassert>
#include <chrono>
#include <iostream>
#include <string>
#include <vector>

using namespace kelpie::linuxapp;
using Clock = std::chrono::steady_clock;

namespace {

const char kId[] = "AAECAwQFBgcICQoLDA0ODw";

void TestInstanceNames() {
  assert(SyncInstanceName({{"id", kId}}) == std::string("kelpie-") + kId);
  assert(SyncInstanceName({}).empty());
  assert(SyncInstanceName({{"id", ""}}).empty());
  assert(SyncInstanceName({{"id", "has space"}}).empty());
  assert(SyncInstanceName({{"id", "dot.ted"}}).empty());
  assert(SyncInstanceName({{"id", std::string(44, 'a')}}).empty());
  assert(!SyncInstanceName({{"id", std::string(43, 'a')}}).empty());
}

void TestTxtRoundTrip() {
  const SyncTxt txt{{"v", "1"}, {"id", kId}, {"h", "q83vASNFZ4k"}};
  const auto entries = EncodeSyncTxt(txt);
  assert((entries == std::vector<std::string>{"h=q83vASNFZ4k", std::string("id=") + kId, "v=1"}));
  assert(DecodeSyncTxt(entries) == txt);

  // Unusable pairs are dropped rather than sent malformed.
  const auto dropped = EncodeSyncTxt({{"", "x"}, {"a=b", "c"}, {"long", std::string(300, 'x')}, {"ok", ""}});
  assert((dropped == std::vector<std::string>{"ok="}));

  // Keys are case-insensitive; the first occurrence wins; no '=' means empty.
  const auto decoded = DecodeSyncTxt({"V=1", "v=2", "flag", "=orphan", "id=a=b"});
  assert(decoded.at("v") == "1");
  assert(decoded.at("flag").empty());
  assert(decoded.at("id") == "a=b");
  assert(decoded.size() == 3);
}

SyncPeerView View(std::vector<std::string> addresses, int port = 4242, std::string id = kId) {
  return SyncPeerView{std::move(addresses), port, {{"v", "1"}, {"id", std::move(id)}}};
}

void TestPeerTable() {
  SyncPeerTable table;
  // Not usable yet: no address.
  assert(!table.Update("kelpie-a", "eth0/4", View({})));
  auto found = table.Update("kelpie-a", "eth0/4", View({"192.168.1.5"}));
  assert(found && found->found && found->advert.instance == "kelpie-a");
  assert((found->advert.addresses == std::vector<std::string>{"192.168.1.5"}));
  // An identical refresh reports nothing.
  assert(!table.Update("kelpie-a", "eth0/4", View({"192.168.1.5"})));
  // A second source merges; IPv4 stays first.
  auto merged = table.Update("kelpie-a", "eth0/6", View({"fe80::1%2"}));
  assert(merged && merged->found);
  assert((merged->advert.addresses == std::vector<std::string>{"192.168.1.5", "fe80::1%2"}));
  merged = table.Update("kelpie-a", "wlan0/4", View({"10.0.0.7", "192.168.1.5"}));
  assert(merged && (merged->advert.addresses ==
                    std::vector<std::string>{"192.168.1.5", "10.0.0.7", "fe80::1%2"}));
  // TXT and port follow the latest source.
  merged = table.Update("kelpie-a", "eth0/4", SyncPeerView{{"192.168.1.5"}, 5000, {{"v", "1"}, {"h", "new"}}});
  assert(merged && merged->advert.port == 5000 && merged->advert.txt.at("h") == "new");
  // Losing one of several sources is an update, not a loss.
  auto partial = table.Remove("kelpie-a", "eth0/6");
  assert(partial && partial->found);
  assert(!table.Remove("kelpie-a", "missing"));
  partial = table.Remove("kelpie-a", "eth0/4");
  assert(partial && partial->found);
  auto lost = table.Remove("kelpie-a", "wlan0/4");
  assert(lost && !lost->found && lost->advert.instance == "kelpie-a");
  assert(!table.Contains("kelpie-a"));
  // Lost exactly once.
  assert(!table.Remove("kelpie-a", "wlan0/4"));

  // A view that stops being usable is a loss; a later usable one is found again.
  assert(table.Update("kelpie-b", "", View({"192.168.1.9"})));
  lost = table.Update("kelpie-b", "", View({}));
  assert(lost && !lost->found);
  assert(!table.Update("kelpie-b", "", View({}, 0)));
  assert(table.Update("kelpie-b", "", View({"192.168.1.9"}))->found);

  // An instance never reported is never reported lost.
  assert(!table.Update("kelpie-c", "", View({}, 0)));
  const auto cleared = table.Clear();
  assert(cleared.size() == 1 && cleared[0].advert.instance == "kelpie-b" && !cleared[0].found);
}

void TestSerialQueue() {
  SyncSerialQueue queue;
  std::vector<int> order;
  std::mutex mutex;
  auto push = [&](int value) {
    return [&, value] {
      std::lock_guard<std::mutex> lock(mutex);
      order.push_back(value);
    };
  };
  queue.PostAt(Clock::now() + std::chrono::milliseconds(60), push(3));
  queue.Post(push(1));
  queue.Post(push(2));
  queue.Flush();
  {
    std::lock_guard<std::mutex> lock(mutex);
    assert((order == std::vector<int>{1, 2}));
  }
  std::this_thread::sleep_for(std::chrono::milliseconds(120));
  queue.Flush();
  std::lock_guard<std::mutex> lock(mutex);
  assert((order == std::vector<int>{1, 2, 3}));
}

void TestDeliveryFence() {
  SyncSerialQueue queue;
  SyncPeerDelivery delivery([&queue](std::function<void()> task) { queue.Post(std::move(task)); });
  std::atomic<int> found{0};
  std::atomic<int> lost{0};
  std::atomic<bool> reentered{false};
  const auto generation = delivery.Begin(
      [&](const kelpie::SyncPeerAdvert& advert) {
        ++found;
        // Callbacks may call back into the owner from the worker thread.
        reentered = queue.OnQueueThread() && delivery.Active() && advert.instance == "kelpie-a";
      },
      [&](const std::string&) { ++lost; });
  SyncPeerTable::Event event{true, kelpie::SyncPeerAdvert{"kelpie-a", {"10.0.0.1"}, 1, {}}};
  delivery.Deliver(generation, event);
  delivery.Deliver(generation, std::nullopt);
  queue.Flush();
  assert(found == 1 && reentered);

  // Events from an ended generation are dropped, including ones already queued.
  queue.Post([] { std::this_thread::sleep_for(std::chrono::milliseconds(30)); });
  delivery.Deliver(generation, SyncPeerTable::Event{false, kelpie::SyncPeerAdvert{"kelpie-a", {}, 0, {}}});
  delivery.End();
  queue.Flush();
  assert(lost == 0 && !delivery.Active());

  const auto next = delivery.Begin([&](const kelpie::SyncPeerAdvert&) { ++found; }, [&](const std::string&) { ++lost; });
  delivery.Deliver(generation, event);
  delivery.Deliver(next, SyncPeerTable::Event{false, kelpie::SyncPeerAdvert{"kelpie-a", {}, 0, {}}});
  queue.Flush();
  assert(found == 1 && lost == 1);
}

void TestRejectsUnusableAdverts() {
  AvahiSyncDiscovery discovery;
  assert(!discovery.Advertise(0, {{"v", "1"}, {"id", kId}}));
  assert(!discovery.Advertise(70000, {{"v", "1"}, {"id", kId}}));
  assert(!discovery.Advertise(4242, {{"v", "1"}}));
  // Stopping what never started is harmless.
  discovery.StopAdvertising();
  discovery.StopBrowsing();
}

}  // namespace

int main() {
  TestInstanceNames();
  TestTxtRoundTrip();
  TestPeerTable();
  TestRejectsUnusableAdverts();
  TestSerialQueue();
  TestDeliveryFence();
  std::cout << "sync discovery tests passed\n";
  return 0;
}
