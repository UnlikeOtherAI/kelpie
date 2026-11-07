#include "owner_task_queue.h"

#include <algorithm>

namespace kelpie::windows {

std::shared_ptr<OwnerTaskQueue::Task> OwnerTaskQueue::Enqueue(std::function<bool()> call) {
  auto task = std::make_shared<Task>();
  task->call = std::move(call);
  std::lock_guard lock(mutex_);
  if (stopping_) task->abandoned = true;
  else pending_.push_back(task);
  return task;
}

bool OwnerTaskQueue::Wait(const std::shared_ptr<Task>& task, std::chrono::milliseconds timeout) {
  if (!task) return false;
  std::unique_lock lock(task->mutex);
  if (task->ready.wait_for(lock, timeout, [&] { return task->done || task->abandoned; })) {
    return task->done && task->succeeded && !task->abandoned;
  }
  if (!task->started) {
    task->abandoned = true;
    task->ready.notify_all();
  }
  return false;
}

void OwnerTaskQueue::RunOne() {
  std::shared_ptr<Task> task;
  {
    std::lock_guard lock(mutex_);
    if (pending_.empty()) return;
    task = pending_.front();
    pending_.erase(pending_.begin());
    active_.push_back(task);
  }
  {
    std::lock_guard lock(task->mutex);
    if (task->abandoned) { RemoveActive(task); return; }
    task->started = true;
  }
  bool succeeded = false;
  try { succeeded = task->call && task->call(); } catch (...) { succeeded = false; }
  Complete(task, succeeded);
  RemoveActive(task);
}

void OwnerTaskQueue::Abandon(const std::shared_ptr<Task>& task) {
  if (!task) return;
  std::lock_guard lock(task->mutex);
  if (!task->done) { task->abandoned = true; task->ready.notify_all(); }
}

void OwnerTaskQueue::Cancel() {
  std::vector<std::shared_ptr<Task>> tasks;
  {
    std::lock_guard lock(mutex_);
    stopping_ = true;
    tasks = pending_;
    tasks.insert(tasks.end(), active_.begin(), active_.end());
    pending_.clear();
  }
  for (const auto& task : tasks) Abandon(task);
}

void OwnerTaskQueue::Complete(const std::shared_ptr<Task>& task, bool succeeded) {
  std::lock_guard lock(task->mutex);
  if (!task->abandoned) { task->succeeded = succeeded; task->done = true; }
  task->ready.notify_all();
}

void OwnerTaskQueue::RemoveActive(const std::shared_ptr<Task>& task) {
  std::lock_guard lock(mutex_);
  std::erase(active_, task);
}

}  // namespace kelpie::windows
