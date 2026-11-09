#pragma once

// The serial executor that owns the core-sync store. Every store call and
// every engine read or write it needs run on one worker thread, so a merge
// transaction (plan → engine writes → read-back → commit) holds the store
// from start to finish and no scan can interleave.

#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>

#include <nlohmann/json.hpp>

#include "kelpie/sync_cookie_store.h"
#include "sync_store.h"

namespace kelpie::desktop_sync {

class StoreHost {
 public:
  using Json = nlohmann::json;
  using Cancelled = SyncCookieStore::Cancelled;

  // `on_head_changed` runs on the executor thread after any call that moved
  // the change feed head; it must not block.
  StoreHost(SyncCookieStore* cookies, std::function<void()> on_head_changed,
            std::function<void(const std::string&)> log);
  ~StoreHost();
  StoreHost(const StoreHost&) = delete;
  StoreHost& operator=(const StoreHost&) = delete;

  bool Open(const std::string& path, const sync::SyncStore::Options& options, std::string* error);
  void Close();

  // Each returns nullopt when the store is closed, the call was cancelled,
  // the engine could not be read or written, or core-sync refused it.
  std::optional<Json> Scan(std::int64_t now, const Cancelled& cancelled);
  std::optional<Json> AnswerPull(const Json& pull, std::int64_t now, const Cancelled& cancelled);
  std::optional<Json> BuildPush(const Json& watermark, std::int64_t now, const Cancelled& cancelled);
  std::optional<Json> Merge(const Json& records, const Json& source, std::int64_t now, const Cancelled& cancelled);
  std::optional<Json> Watermark(const std::string& replica);
  void FinishWarmup();
  void PostScan(std::int64_t now, Cancelled cancelled);

  // Counts from the last executor call; never blocks on the executor.
  Json Status() const;

 private:
  template <typename Task>
  auto Run(Task&& task) -> decltype(task());
  void Post(std::function<void()> task);
  void Worker();
  void Refresh();  // on the executor: cache status, report head movement
  std::optional<Json> Guard(const char* what, const std::function<Json()>& call);

  SyncCookieStore* cookies_;
  std::function<void()> on_head_changed_;
  std::function<void(const std::string&)> log_;
  std::unique_ptr<sync::SyncStore> store_;  // executor thread only

  std::mutex queue_mutex_;
  std::condition_variable queue_ready_;
  std::deque<std::function<void()>> queue_;
  bool stopping_ = false;
  std::thread worker_;

  mutable std::mutex status_mutex_;
  Json status_ = Json::object();
  std::uint64_t head_ = 0;
};

}  // namespace kelpie::desktop_sync
