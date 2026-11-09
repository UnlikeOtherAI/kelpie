// Discovery rules that do not need the OS: TXT encoding, instance names, the
// per-instance merge, the Windows browse record cache and serial delivery.
#include "dnssd_browse_cache.h"
#include "sync_peer_events.h"

#include <atomic>
#include <cassert>
#include <chrono>
#include <iostream>
#include <string>
#include <vector>

using namespace kelpie::windows;
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

DnsSdRecord Ptr(const std::string& instance, std::uint32_t ttl = 4500) {
  DnsSdRecord record;
  record.type = DnsSdRecord::Type::kPtr;
  record.name = "_kelpie-sync._tcp.local";
  record.target = instance + "._kelpie-sync._tcp.local";
  record.ttl = ttl;
  return record;
}

DnsSdRecord Srv(const std::string& instance, const std::string& host, int port, std::uint32_t ttl = 120) {
  DnsSdRecord record;
  record.type = DnsSdRecord::Type::kSrv;
  record.name = instance + "._kelpie-sync._tcp.local";
  record.target = host;
  record.port = port;
  record.ttl = ttl;
  return record;
}

DnsSdRecord Txt(const std::string& instance, std::vector<std::string> entries) {
  DnsSdRecord record;
  record.type = DnsSdRecord::Type::kTxt;
  record.name = instance + "._kelpie-sync._tcp.local";
  record.txt = std::move(entries);
  record.ttl = 4500;
  return record;
}

DnsSdRecord Address(const std::string& host, const std::string& address, std::uint32_t ttl = 120) {
  DnsSdRecord record;
  record.type = DnsSdRecord::Type::kAddress;
  record.name = host;
  record.address = address;
  record.ttl = ttl;
  return record;
}

void TestBrowseCacheAnswers() {
  DnsSdBrowseCache cache("_kelpie-sync._tcp.local");
  const auto now = Clock::now();
  // One answer per interface, as Windows delivers them.
  auto result = cache.Apply({Ptr("kelpie-Mac"), Srv("kelpie-Mac", "studio.local", 50001),
                             Txt("kelpie-Mac", {"v=1", "id=Mac", "h=x"}),
                             Address("studio.local", "192.168.1.229")},
                            now);
  assert(result.changes.size() == 1 && result.resolve.empty());
  assert(result.changes[0].instance == "kelpie-Mac");
  assert(result.changes[0].view->port == 50001);
  assert(result.changes[0].view->txt.at("id") == "Mac");
  result = cache.Apply({Ptr("kelpie-Mac"), Srv("kelpie-Mac", "studio.local", 50001),
                        Address("STUDIO.local.", "192.168.1.61")},
                       now);
  assert(result.changes.size() == 1);
  assert((result.changes[0].view->addresses == std::vector<std::string>{"192.168.1.229", "192.168.1.61"}));

  // A goodbye removes the instance, case-insensitively.
  result = cache.Apply({Ptr("KELPIE-mac", 0)}, now);
  assert(result.changes.size() == 1 && !result.changes[0].view);
  assert(result.changes[0].instance == "kelpie-Mac");
  result = cache.Apply({Ptr("kelpie-Mac", 0)}, now);
  assert(result.changes.empty());

  // Other services and our own advertisement are ignored.
  cache.SetOwnInstance("kelpie-Self._kelpie-sync._tcp.local");
  DnsSdRecord other = Ptr("printer");
  other.name = "_ipp._tcp.local";
  result = cache.Apply({other, Ptr("kelpie-self"), Srv("kelpie-Self", "me.local", 1)}, now);
  assert(result.changes.empty());

  // SRV or TXT for an instance the browse never saw is not trusted.
  result = cache.Apply({Srv("kelpie-ghost", "ghost.local", 9), Txt("kelpie-ghost", {"v=1"})}, now);
  assert(result.changes.empty());
}

void TestBrowseCacheResolveAndExpiry() {
  DnsSdBrowseCache cache("_kelpie-sync._tcp.local");
  const auto now = Clock::now();
  // A PTR alone asks for a resolve.
  auto result = cache.Apply({Ptr("kelpie-Win", 60)}, now);
  assert(result.changes.size() == 1 && result.changes[0].view->addresses.empty());
  assert((result.resolve == std::vector<std::string>{"kelpie-win._kelpie-sync._tcp.local"}));
  result = cache.Resolved("kelpie-win._kelpie-sync._tcp.local", "maxis.local", 50002, {"v=1", "id=Win"},
                          {"192.168.1.90", "fe80::5%17"}, now);
  assert(result.changes.size() == 1 && result.resolve.empty());
  assert(result.changes[0].view->port == 50002);
  assert((result.changes[0].view->addresses == std::vector<std::string>{"192.168.1.90", "fe80::5%17"}));

  // Host records shorter than the minimum lifetime do not flap.
  cache.Apply({Ptr("kelpie-Win", 4500), Srv("kelpie-Win", "maxis.local", 50002), Address("maxis.local", "10.1.1.1", 1)},
              now);
  result = cache.Expire(now + std::chrono::seconds(5));
  assert(result.changes.empty());
  result = cache.Expire(now + DnsSdBrowseCache::kMinAddressLifetime + std::chrono::seconds(1));
  assert(result.changes.size() == 1 && result.changes[0].view);
  assert(result.changes[0].view->addresses.empty());

  // The PTR TTL ends the instance.
  result = cache.Expire(now + std::chrono::seconds(4501));
  assert(result.changes.size() == 1 && !result.changes[0].view);
  assert(!cache.NextExpiry() || *cache.NextExpiry() > now);

  // A resolve answer that arrives after the goodbye never resurrects it.
  cache.Apply({Ptr("kelpie-Late")}, now);
  cache.Apply({Ptr("kelpie-Late", 0)}, now);
  result = cache.Resolved("kelpie-late._kelpie-sync._tcp.local", "late.local", 1, {}, {"10.0.0.1"}, now);
  assert(result.changes.empty());
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

}  // namespace

int main() {
  TestInstanceNames();
  TestTxtRoundTrip();
  TestPeerTable();
  TestBrowseCacheAnswers();
  TestBrowseCacheResolveAndExpiry();
  TestSerialQueue();
  TestDeliveryFence();
  std::cout << "sync discovery tests passed\n";
  return 0;
}
