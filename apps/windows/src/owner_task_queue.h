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
    std::function<void()> call;
    std::mutex mutex;
    std::condition_variable ready;
    bool started = false;
    bool done = false;
    bool abandoned = false;
  };
  std::shared_ptr<Task> Enqueue(std::function<void()> call);
  bool Wait(const std::shared_ptr<Task>& task, std::chrono::milliseconds timeout);
  void RunOne();
  void Cancel();
 private:
  std::mutex mutex_;
  std::vector<std::shared_ptr<Task>> tasks_;
  bool stopping_ = false;
};
}
