#pragma once

#include <chrono>
#include <condition_variable>
#include <functional>
#include <memory>
#include <mutex>
#include <vector>

namespace kelpie::windows {

class OwnerTaskQueue {
 public:
  struct Task {
    std::function<bool()> call;
    std::mutex mutex;
    std::condition_variable ready;
    bool started = false;
    bool done = false;
    bool abandoned = false;
    bool succeeded = false;
  };

  std::shared_ptr<Task> Enqueue(std::function<bool()> call);
  bool Wait(const std::shared_ptr<Task>& task, std::chrono::milliseconds timeout);
  void RunOne();
  void Abandon(const std::shared_ptr<Task>& task);
  void Cancel();

 private:
  void Complete(const std::shared_ptr<Task>& task, bool succeeded);
  void RemoveActive(const std::shared_ptr<Task>& task);

  std::mutex mutex_;
  std::vector<std::shared_ptr<Task>> pending_;
  std::vector<std::shared_ptr<Task>> active_;
  bool stopping_ = false;
};

}  // namespace kelpie::windows
