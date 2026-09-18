#include "owner_task_queue.h"

using kelpie::windows::OwnerTaskQueue;

int main() {
  OwnerTaskQueue queue;
  int called = 0;
  auto success = queue.Enqueue([&] { ++called; return true; });
  queue.RunOne();
  if (!queue.Wait(success, std::chrono::milliseconds(1)) || called != 1) return 1;
  auto failure = queue.Enqueue([] { return false; });
  queue.RunOne();
  if (queue.Wait(failure, std::chrono::milliseconds(1))) return 2;
  auto expired = queue.Enqueue([&] { ++called; return true; });
  if (queue.Wait(expired, std::chrono::milliseconds::zero())) return 3;
  queue.RunOne();
  if (called != 1) return 4;
  auto cancelled = queue.Enqueue([&] { ++called; return true; });
  queue.Cancel();
  return queue.Wait(cancelled, std::chrono::milliseconds(1)) ? 5 : 0;
}
