#pragma once

// Platform-neutral pieces of `_kelpie-sync._tcp` discovery: TXT encoding,
// instance naming, merging per-source peer views and serial event delivery.
// No OS API is used here, so every rule is unit-tested without mDNS.

#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <map>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

#include "kelpie/desktop_sync.h"

namespace kelpie::windows {

using SyncTxt = std::map<std::string, std::string>;

inline constexpr char kSyncServiceType[] = "_kelpie-sync._tcp";
inline constexpr char kSyncInstancePrefix[] = "kelpie-";

// "kelpie-<replicaId>". The replica id is new on every launch and sign-in, so
// the name never identifies a device across runs. Empty when `id` is missing
// or is not 1..43 base64url characters.
std::string SyncInstanceName(const SyncTxt& txt);

// RFC 6763 "key=value" strings. Pairs that cannot be carried (empty key, '='
// in the key, non-printable key or over 255 bytes) are dropped.
std::vector<std::string> EncodeSyncTxt(const SyncTxt& txt);

// Keys are case-insensitive and only the first occurrence counts (RFC 6763
// 6.4); an entry without '=' is a key with an empty value.
SyncTxt DecodeSyncTxt(const std::vector<std::string>& entries);

// One source's view of an instance: the merged record cache on Windows, one
// interface and protocol on Avahi.
struct SyncPeerView {
  std::vector<std::string> addresses;
  int port = 0;
  SyncTxt txt;
};

// Merges views per instance. An instance is reported found once it has a
// port and at least one address, again only when its merged advert changes,
// and lost once when its last usable view goes away.
class SyncPeerTable {
 public:
  struct Event {
    bool found = false;  // false: lost
    SyncPeerAdvert advert;
  };

  std::optional<Event> Update(const std::string& instance, const std::string& source,
                              SyncPeerView view);
  std::optional<Event> Remove(const std::string& instance, const std::string& source);
  // Lost for every reported instance; forgets everything.
  std::vector<Event> Clear();
  bool Contains(const std::string& instance) const { return entries_.count(instance) != 0; }

 private:
  struct Entry {
    std::map<std::string, SyncPeerView> sources;
    std::string latest_source;
    std::optional<SyncPeerAdvert> reported;
  };
  std::optional<Event> Report(const std::string& instance, Entry& entry);

  std::map<std::string, Entry> entries_;
};

// A single worker thread for discovery: it runs posted and delayed tasks in
// order and is where found/lost are delivered, so callbacks never run on an
// OS callback thread or under a discovery lock. Never destroy it from one of
// its own tasks.
class SyncSerialQueue {
 public:
  using Clock = std::chrono::steady_clock;

  SyncSerialQueue();
  ~SyncSerialQueue();
  SyncSerialQueue(const SyncSerialQueue&) = delete;
  SyncSerialQueue& operator=(const SyncSerialQueue&) = delete;

  void Post(std::function<void()> task);
  void PostAt(Clock::time_point when, std::function<void()> task);
  bool OnQueueThread() const;
  // Waits until every task that is already due has run. For tests.
  void Flush();

 private:
  struct Task {
    Clock::time_point when;
    std::uint64_t order = 0;
    std::function<void()> run;
  };
  void Run();

  mutable std::mutex mutex_;
  std::condition_variable wake_;
  std::condition_variable idle_;
  std::vector<Task> tasks_;
  std::uint64_t next_order_ = 0;
  bool running_task_ = false;
  bool stop_ = false;
  std::thread thread_;
};

// Holds the browse callbacks and delivers table events in posting order
// through `post` (the discovery's serial queue). A browse generation fences
// delivery: once End() returns no callback is running or will start. End()
// waits for a callback in progress, so its caller must not hold a lock that
// callback needs; called from inside a callback it returns at once.
class SyncPeerDelivery {
 public:
  using Found = std::function<void(const SyncPeerAdvert&)>;
  using Lost = std::function<void(const std::string&)>;
  using Post = std::function<void(std::function<void()>)>;

  explicit SyncPeerDelivery(Post post) : post_(std::move(post)) {}

  std::uint64_t Begin(Found found, Lost lost);
  void End();
  bool Active() const;
  std::uint64_t generation() const;
  void Deliver(std::uint64_t generation, std::optional<SyncPeerTable::Event> event);

 private:
  Post post_;
  mutable std::mutex mutex_;
  std::condition_variable idle_;
  std::uint64_t generation_ = 0;
  bool active_ = false;
  bool running_ = false;
  std::thread::id running_thread_;
  Found found_;
  Lost lost_;
};

}  // namespace kelpie::windows
