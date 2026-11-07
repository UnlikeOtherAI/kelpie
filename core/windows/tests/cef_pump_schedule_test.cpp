#include "cef_pump_schedule.h"

#include <cassert>

using kelpie::windows::CefPumpScheduler;
using Action = kelpie::windows::CefPumpScheduler::Action;

namespace {

// An immediate request must pump right away and cancel any armed timer.
void ImmediateRequestRunsWork() {
  CefPumpScheduler scheduler;
  const auto armed = scheduler.OnScheduleWork(500);
  assert(armed.action == Action::kArmTimer);
  assert(armed.delay_ms == kelpie::windows::kMaxCefPumpDelayMs);
  assert(scheduler.timer_pending());

  const auto immediate = scheduler.OnScheduleWork(0);
  assert(immediate.action == Action::kRunWork);
  assert(!scheduler.timer_pending());
}

// CEF passes a negative delay to mean "as soon as possible", never "later".
void NegativeDelayRunsWork() {
  CefPumpScheduler scheduler;
  assert(scheduler.OnScheduleWork(-1).action == Action::kRunWork);
}

// A short delay is honoured; a long one is capped so the pump keeps ticking.
void DelayIsCapped() {
  CefPumpScheduler scheduler;
  const auto soon = scheduler.OnScheduleWork(5);
  assert(soon.action == Action::kArmTimer && soon.delay_ms == 5);

  CefPumpScheduler other;
  const auto late = other.OnScheduleWork(60000);
  assert(late.action == Action::kArmTimer);
  assert(late.delay_ms == kelpie::windows::kMaxCefPumpDelayMs);
}

// The regression: after a pump completes, a wake-up must always remain armed.
// CEF latches OnScheduleMessagePumpWork() and will not necessarily announce
// work it already holds, so a pump that ends with nothing scheduled strands
// every task posted with CefPostTask(TID_UI).
void EveryPumpLeavesAWakeUpArmed() {
  CefPumpScheduler scheduler;
  assert(scheduler.OnScheduleWork(0).action == Action::kRunWork);

  assert(scheduler.BeginWork());
  const auto after = scheduler.EndWork();
  assert(after.action == Action::kArmTimer);
  assert(after.delay_ms == kelpie::windows::kMaxCefPumpDelayMs);
  assert(scheduler.timer_pending());
  assert(!scheduler.running());

  // The armed timer pumps again, and that pump re-arms in its turn: the chain
  // never terminates while the runtime is up.
  assert(scheduler.OnTimerElapsed().action == Action::kRunWork);
  assert(!scheduler.timer_pending());
  assert(scheduler.BeginWork());
  assert(scheduler.EndWork().action == Action::kArmTimer);
}

// A pump already scheduled by CEF is not doubled up by the heartbeat.
void PendingTimerSuppressesHeartbeat() {
  CefPumpScheduler scheduler;
  assert(scheduler.BeginWork());
  // CEF asks for a delayed pump from inside CefDoMessageLoopWork().
  assert(scheduler.OnScheduleWork(10).action == Action::kArmTimer);
  assert(scheduler.EndWork().action == Action::kNone);
  assert(scheduler.timer_pending());
}

// CefDoMessageLoopWork() must never be re-entered; the request is deferred and
// replayed once the outer pump returns.
void ReentrantRequestIsDeferred() {
  CefPumpScheduler scheduler;
  assert(scheduler.BeginWork());
  assert(!scheduler.BeginWork());
  assert(scheduler.running());

  const auto after = scheduler.EndWork();
  assert(after.action == Action::kPostWork);
  assert(!scheduler.running());

  // The replayed pump is a normal one and re-arms the heartbeat.
  assert(scheduler.BeginWork());
  assert(scheduler.EndWork().action == Action::kArmTimer);
}

// Shutdown drops every pending wake-up so no pump outlives CefShutdown().
void ResetClearsPendingState() {
  CefPumpScheduler scheduler;
  assert(scheduler.BeginWork());
  assert(!scheduler.BeginWork());
  scheduler.OnScheduleWork(10);
  scheduler.Reset();
  assert(!scheduler.running());
  assert(!scheduler.timer_pending());
  assert(scheduler.BeginWork());
  assert(scheduler.EndWork().action == Action::kArmTimer);
}

}  // namespace

int main() {
  ImmediateRequestRunsWork();
  NegativeDelayRunsWork();
  DelayIsCapped();
  EveryPumpLeavesAWakeUpArmed();
  PendingTimerSuppressesHeartbeat();
  ReentrantRequestIsDeferred();
  ResetClearsPendingState();
  return 0;
}
