#include "cef_pump_schedule.h"

#include <algorithm>

namespace kelpie::windows {

CefPumpScheduler::Decision CefPumpScheduler::OnScheduleWork(std::int64_t delay_ms) {
  if (delay_ms <= 0) {
    // CEF cancels any pending scheduled pump when it asks for an immediate one.
    timer_pending_ = false;
    return {Action::kRunWork, 0};
  }
  timer_pending_ = true;
  return {Action::kArmTimer, std::min(delay_ms, kMaxCefPumpDelayMs)};
}

CefPumpScheduler::Decision CefPumpScheduler::OnTimerElapsed() {
  timer_pending_ = false;
  return {Action::kRunWork, 0};
}

bool CefPumpScheduler::BeginWork() {
  if (running_) {
    deferred_ = true;
    return false;
  }
  running_ = true;
  return true;
}

CefPumpScheduler::Decision CefPumpScheduler::EndWork() {
  running_ = false;
  if (deferred_) {
    // A nested pump request arrived while CEF was already pumping. Run it as
    // soon as the current message returns rather than waiting for a timer.
    deferred_ = false;
    return {Action::kPostWork, 0};
  }
  if (timer_pending_) return {Action::kNone, 0};
  // CEF will not necessarily announce the work it already holds, so guarantee
  // the next pump ourselves.
  timer_pending_ = true;
  return {Action::kArmTimer, kMaxCefPumpDelayMs};
}

void CefPumpScheduler::Reset() {
  running_ = false;
  deferred_ = false;
  timer_pending_ = false;
}

}  // namespace kelpie::windows
