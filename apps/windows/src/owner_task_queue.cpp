#include "owner_task_queue.h"
namespace kelpie::windows {
std::shared_ptr<OwnerTaskQueue::Task> OwnerTaskQueue::Enqueue(std::function<void()> call) {
  auto task = std::make_shared<Task>(); task->call = std::move(call);
  std::lock_guard lock(mutex_); if (stopping_) task->abandoned = true; else tasks_.push_back(task); return task;
}
bool OwnerTaskQueue::Wait(const std::shared_ptr<Task>& task, std::chrono::milliseconds timeout) {
  std::unique_lock lock(task->mutex);
  if (task->ready.wait_for(lock, timeout, [&] { return task->done || task->abandoned; })) return task->done;
  if (!task->started) task->abandoned = true;
  return false;
}
void OwnerTaskQueue::RunOne() {
  std::shared_ptr<Task> task; { std::lock_guard lock(mutex_); if (tasks_.empty()) return; task=tasks_.front(); tasks_.erase(tasks_.begin()); }
  { std::lock_guard lock(task->mutex); if (task->abandoned) return; task->started=true; }
  try { task->call(); } catch (...) {}
  { std::lock_guard lock(task->mutex); task->done=true; } task->ready.notify_all();
}
void OwnerTaskQueue::Cancel() {
  std::vector<std::shared_ptr<Task>> tasks; { std::lock_guard lock(mutex_); stopping_=true; tasks.swap(tasks_); }
  for (auto& task:tasks) { std::lock_guard lock(task->mutex); task->abandoned=true; task->ready.notify_all(); }
}
}
