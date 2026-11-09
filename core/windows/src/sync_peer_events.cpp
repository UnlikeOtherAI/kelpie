#include "sync_peer_events.h"

#include <algorithm>
#include <cctype>

namespace kelpie::windows {
namespace {

constexpr std::size_t kMaxReplicaIdLength = 43;
constexpr std::size_t kMaxTxtEntryLength = 255;

bool IsBase64Url(char c) {
  return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' ||
         c == '_';
}

bool IsTxtKey(const std::string& key) {
  if (key.empty()) return false;
  return std::all_of(key.begin(), key.end(), [](char c) {
    return c >= 0x20 && c <= 0x7E && c != '=';
  });
}

std::string LowerAscii(std::string value) {
  for (char& c : value) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return value;
}

bool IsIpv6(const std::string& address) { return address.find(':') != std::string::npos; }

bool SameAdvert(const SyncPeerAdvert& left, const SyncPeerAdvert& right) {
  return left.instance == right.instance && left.addresses == right.addresses &&
         left.port == right.port && left.txt == right.txt;
}

}  // namespace

std::string SyncInstanceName(const SyncTxt& txt) {
  const auto id = txt.find("id");
  if (id == txt.end() || id->second.empty() || id->second.size() > kMaxReplicaIdLength) return {};
  if (!std::all_of(id->second.begin(), id->second.end(), IsBase64Url)) return {};
  return kSyncInstancePrefix + id->second;
}

std::vector<std::string> EncodeSyncTxt(const SyncTxt& txt) {
  std::vector<std::string> entries;
  for (const auto& [key, value] : txt) {
    if (!IsTxtKey(key)) continue;
    std::string entry = key + "=" + value;
    if (entry.size() > kMaxTxtEntryLength) continue;
    entries.push_back(std::move(entry));
  }
  return entries;
}

SyncTxt DecodeSyncTxt(const std::vector<std::string>& entries) {
  SyncTxt txt;
  for (const auto& entry : entries) {
    const auto split = entry.find('=');
    std::string key = LowerAscii(entry.substr(0, split));
    if (!IsTxtKey(key)) continue;
    txt.emplace(std::move(key), split == std::string::npos ? std::string() : entry.substr(split + 1));
  }
  return txt;
}

std::optional<SyncPeerTable::Event> SyncPeerTable::Update(const std::string& instance,
                                                          const std::string& source,
                                                          SyncPeerView view) {
  auto& entry = entries_[instance];
  entry.sources[source] = std::move(view);
  entry.latest_source = source;
  return Report(instance, entry);
}

std::optional<SyncPeerTable::Event> SyncPeerTable::Remove(const std::string& instance,
                                                          const std::string& source) {
  const auto found = entries_.find(instance);
  if (found == entries_.end()) return std::nullopt;
  auto& entry = found->second;
  entry.sources.erase(source);
  if (entry.latest_source == source) {
    entry.latest_source = entry.sources.empty() ? std::string() : entry.sources.begin()->first;
  }
  auto event = Report(instance, entry);
  if (entry.sources.empty()) entries_.erase(found);
  return event;
}

std::vector<SyncPeerTable::Event> SyncPeerTable::Clear() {
  std::vector<Event> events;
  for (auto& [instance, entry] : entries_) {
    if (entry.reported) events.push_back({false, SyncPeerAdvert{instance, {}, 0, {}}});
  }
  entries_.clear();
  return events;
}

std::optional<SyncPeerTable::Event> SyncPeerTable::Report(const std::string& instance, Entry& entry) {
  SyncPeerAdvert merged;
  merged.instance = instance;
  const auto latest = entry.sources.find(entry.latest_source);
  if (latest != entry.sources.end()) {
    merged.port = latest->second.port;
    merged.txt = latest->second.txt;
  }
  // IPv4 first: the spec prefers IPv4 and link-local for outgoing connections.
  for (const bool want_ipv6 : {false, true}) {
    for (const auto& [source, view] : entry.sources) {
      for (const auto& address : view.addresses) {
        if (address.empty() || IsIpv6(address) != want_ipv6) continue;
        if (std::find(merged.addresses.begin(), merged.addresses.end(), address) ==
            merged.addresses.end()) {
          merged.addresses.push_back(address);
        }
      }
    }
  }
  const bool usable = merged.port > 0 && merged.port <= 65535 && !merged.addresses.empty();
  if (!usable) {
    if (!entry.reported) return std::nullopt;
    entry.reported.reset();
    return Event{false, SyncPeerAdvert{instance, {}, 0, {}}};
  }
  if (entry.reported && SameAdvert(*entry.reported, merged)) return std::nullopt;
  entry.reported = merged;
  return Event{true, std::move(merged)};
}

SyncSerialQueue::SyncSerialQueue() : thread_([this] { Run(); }) {}

SyncSerialQueue::~SyncSerialQueue() {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    stop_ = true;
    tasks_.clear();
  }
  wake_.notify_all();
  idle_.notify_all();
  if (thread_.joinable()) thread_.join();
}

void SyncSerialQueue::Post(std::function<void()> task) { PostAt(Clock::now(), std::move(task)); }

void SyncSerialQueue::PostAt(Clock::time_point when, std::function<void()> task) {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (stop_) return;
    tasks_.push_back({when, next_order_++, std::move(task)});
  }
  wake_.notify_all();
}

bool SyncSerialQueue::OnQueueThread() const { return std::this_thread::get_id() == thread_.get_id(); }

void SyncSerialQueue::Flush() {
  std::unique_lock<std::mutex> lock(mutex_);
  idle_.wait(lock, [this] {
    if (stop_) return true;
    if (running_task_) return false;
    const auto now = Clock::now();
    return std::none_of(tasks_.begin(), tasks_.end(), [now](const Task& task) { return task.when <= now; });
  });
}

void SyncSerialQueue::Run() {
  std::unique_lock<std::mutex> lock(mutex_);
  while (!stop_) {
    auto next = std::min_element(tasks_.begin(), tasks_.end(), [](const Task& left, const Task& right) {
      return left.when != right.when ? left.when < right.when : left.order < right.order;
    });
    if (next == tasks_.end()) {
      idle_.notify_all();
      wake_.wait(lock);
      continue;
    }
    if (next->when > Clock::now()) {
      idle_.notify_all();
      wake_.wait_until(lock, next->when);
      continue;
    }
    auto run = std::move(next->run);
    tasks_.erase(next);
    running_task_ = true;
    lock.unlock();
    run();
    lock.lock();
    running_task_ = false;
  }
  idle_.notify_all();
}

std::uint64_t SyncPeerDelivery::Begin(Found found, Lost lost) {
  std::lock_guard<std::mutex> lock(mutex_);
  ++generation_;
  active_ = true;
  found_ = std::move(found);
  lost_ = std::move(lost);
  return generation_;
}

void SyncPeerDelivery::End() {
  std::unique_lock<std::mutex> lock(mutex_);
  ++generation_;
  active_ = false;
  found_ = nullptr;
  lost_ = nullptr;
  if (running_thread_ == std::this_thread::get_id()) return;
  idle_.wait(lock, [this] { return !running_; });
}

bool SyncPeerDelivery::Active() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return active_;
}

std::uint64_t SyncPeerDelivery::generation() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return generation_;
}

void SyncPeerDelivery::Deliver(std::uint64_t generation, std::optional<SyncPeerTable::Event> event) {
  if (!event) return;
  post_([this, generation, event = std::move(*event)] {
    Found found;
    Lost lost;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (!active_ || generation != generation_) return;
      found = found_;
      lost = lost_;
      running_ = true;
      running_thread_ = std::this_thread::get_id();
    }
    if (event.found) {
      if (found) found(event.advert);
    } else if (lost) {
      lost(event.advert.instance);
    }
    {
      std::lock_guard<std::mutex> lock(mutex_);
      running_ = false;
      running_thread_ = {};
    }
    idle_.notify_all();
  });
}

}  // namespace kelpie::windows
