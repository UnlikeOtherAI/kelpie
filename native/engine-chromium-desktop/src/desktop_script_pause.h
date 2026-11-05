#pragma once
#include <algorithm>
#include <chrono>
#include <stdexcept>

namespace kelpie {
// Revalidation time counts toward the requested monotonic wait.
template <class Clock, class Cancelled, class Sleep>
void PauseDesktopScript(std::chrono::milliseconds requested, Cancelled cancelled, Sleep sleep) {
  if (requested.count() <= 0) return;
  using Duration=typename Clock::duration;
  const auto deadline=Clock::now()+requested;
  const auto slice=std::chrono::duration_cast<Duration>(std::chrono::milliseconds(20));
  for (;;) {
    if (cancelled()) throw std::runtime_error("SCRIPT_STOPPED");
    const auto remaining=deadline-Clock::now();
    if (remaining<=Duration::zero()) return;
    sleep(std::min(remaining,slice));
  }
}
}
