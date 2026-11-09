#include "sync_store_host.h"

#include <future>

namespace kelpie::desktop_sync {

StoreHost::StoreHost(SyncCookieStore* cookies, std::function<void()> on_head_changed,
                     std::function<void(const std::string&)> log)
    : cookies_(cookies), on_head_changed_(std::move(on_head_changed)), log_(std::move(log)),
      worker_([this] { Worker(); }) {}

StoreHost::~StoreHost() {
  Close();
  {
    std::lock_guard lock(queue_mutex_);
    stopping_ = true;
  }
  queue_ready_.notify_all();
  if (worker_.joinable()) worker_.join();
}

void StoreHost::Worker() {
  while (true) {
    std::function<void()> task;
    {
      std::unique_lock lock(queue_mutex_);
      queue_ready_.wait(lock, [this] { return stopping_ || !queue_.empty(); });
      if (queue_.empty()) return;  // stopping with nothing left
      task = std::move(queue_.front());
      queue_.pop_front();
    }
    task();
  }
}

void StoreHost::Post(std::function<void()> task) {
  {
    std::lock_guard lock(queue_mutex_);
    if (stopping_) return;
    queue_.push_back(std::move(task));
  }
  queue_ready_.notify_one();
}

template <typename Task>
auto StoreHost::Run(Task&& task) -> decltype(task()) {
  using Result = decltype(task());
  auto promise = std::make_shared<std::promise<Result>>();
  auto future = promise->get_future();
  {
    std::lock_guard lock(queue_mutex_);
    if (stopping_) return Result{};
    queue_.push_back([promise, task = std::forward<Task>(task)]() mutable {
      try {
        promise->set_value(task());
      } catch (...) {
        promise->set_value(Result{});
      }
    });
  }
  queue_ready_.notify_one();
  return future.get();
}

std::optional<StoreHost::Json> StoreHost::Guard(const char* what, const std::function<Json()>& call) {
  try {
    Json result = call();
    if (result.is_object() && result.contains("error")) return std::nullopt;
    return result;
  } catch (const sync::SyncError& error) {
    // Codes only: messages can describe store contents.
    if (log_) log_(std::string("cookie-sync: ") + what + " refused: " + error.code);
  } catch (const std::exception&) {
    if (log_) log_(std::string("cookie-sync: ") + what + " failed");
  }
  return std::nullopt;
}

void StoreHost::Refresh() {
  if (!store_) return;
  Json status = store_->Status();
  const std::uint64_t head = status.value("head", std::uint64_t{0});
  bool moved = false;
  {
    std::lock_guard lock(status_mutex_);
    moved = head != head_;
    head_ = head;
    status_ = std::move(status);
  }
  if (moved && on_head_changed_) on_head_changed_();
}

bool StoreHost::Open(const std::string& path, const sync::SyncStore::Options& options, std::string* error) {
  return Run([&]() -> bool {
    store_.reset();
    try {
      store_ = sync::SyncStore::Open(path, options);
    } catch (const sync::SyncError& failure) {
      if (error) *error = failure.code;
      return false;
    }
    {
      std::lock_guard lock(status_mutex_);
      head_ = 0;
    }
    Refresh();
    return true;
  });
}

void StoreHost::Close() {
  Run([this]() -> bool {
    store_.reset();
    std::lock_guard lock(status_mutex_);
    status_ = Json::object();
    head_ = 0;
    return true;
  });
}

std::optional<StoreHost::Json> StoreHost::Scan(std::int64_t now, const Cancelled& cancelled) {
  return Run([&]() -> std::optional<Json> {
    if (!store_ || cancelled()) return std::nullopt;
    Json cookies, coverage;
    if (!cookies_->Snapshot(&cookies, &coverage, cancelled) || cancelled()) return std::nullopt;
    auto result = Guard("scan", [&] { return store_->Scan(cookies, coverage, now); });
    Refresh();
    return result;
  });
}

void StoreHost::PostScan(std::int64_t now, Cancelled cancelled) {
  Post([this, now, cancelled = std::move(cancelled)] {
    if (!store_ || cancelled()) return;
    Json cookies, coverage;
    if (!cookies_->Snapshot(&cookies, &coverage, cancelled) || cancelled()) return;
    Guard("scan", [&] { return store_->Scan(cookies, coverage, now); });
    Refresh();
  });
}

std::optional<StoreHost::Json> StoreHost::AnswerPull(const Json& pull, std::int64_t now, const Cancelled& cancelled) {
  return Run([&]() -> std::optional<Json> {
    if (!store_ || cancelled()) return std::nullopt;
    Json cookies = Json::array(), coverage = {{"all", true}};
    // A warming store answers without reading the engine.
    if (!store_->Status().value("warming", false) &&
        (!cookies_->Snapshot(&cookies, &coverage, cancelled) || cancelled())) {
      return std::nullopt;
    }
    auto result = Guard("pull", [&] { return store_->AnswerPull(pull, cookies, coverage, now); });
    Refresh();
    return result;
  });
}

std::optional<StoreHost::Json> StoreHost::BuildPush(const Json& watermark, std::int64_t now,
                                                    const Cancelled& cancelled) {
  return Run([&]() -> std::optional<Json> {
    if (!store_ || cancelled()) return std::nullopt;
    if (store_->Status().value("warming", false)) return Json{{"push", nullptr}};
    Json cookies, coverage;
    if (!cookies_->Snapshot(&cookies, &coverage, cancelled) || cancelled()) return std::nullopt;
    auto result = Guard("push", [&] { return store_->BuildPush(watermark, cookies, coverage, now); });
    Refresh();
    return result;
  });
}

std::optional<StoreHost::Json> StoreHost::Merge(const Json& records, const Json& source, std::int64_t now,
                                                const Cancelled& cancelled) {
  return Run([&]() -> std::optional<Json> {
    if (!store_ || cancelled()) return std::nullopt;
    const auto plan = Guard("merge", [&] { return store_->PlanMerge(records, source, now); });
    if (!plan) return std::nullopt;
    const Json& ops = plan->at("ops");
    Json results = Json::array();
    if (!ops.empty()) {
      results = cookies_->Apply(ops, cancelled);
      // Re-check after the asynchronous engine writes: an old generation's
      // transaction never commits, and a short result never fakes success.
      if (cancelled() || !results.is_array() || results.size() != ops.size()) {
        store_->AbortMerge();
        return std::nullopt;
      }
    }
    auto committed = Guard("commit", [&] { return store_->CommitMerge(results); });
    Refresh();
    return committed;
  });
}

std::optional<StoreHost::Json> StoreHost::Watermark(const std::string& replica) {
  return Run([&]() -> std::optional<Json> {
    if (!store_) return std::nullopt;
    return Guard("watermark", [&] { return store_->Watermark(replica); });
  });
}

void StoreHost::FinishWarmup() {
  Run([this]() -> bool {
    if (store_) store_->FinishWarmup();
    Refresh();
    return true;
  });
}

StoreHost::Json StoreHost::Status() const {
  std::lock_guard lock(status_mutex_);
  return status_;
}

}  // namespace kelpie::desktop_sync
