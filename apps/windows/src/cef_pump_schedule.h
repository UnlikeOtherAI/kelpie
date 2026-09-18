#pragma once

#include <cstdint>

namespace kelpie::windows {

// Longest gap Kelpie is willing to leave between two CefDoMessageLoopWork()
// calls while the Chromium runtime is up.
inline constexpr std::int64_t kMaxCefPumpDelayMs = 1000 / 30;

// Drives the external Chromium message pump on the Win32 UI thread.
//
// CEF only reports "work is waiting" through OnScheduleMessagePumpWork(), and
// it latches that notification: once it has asked for a pump it stays silent
// until it observes that pump happen on the UI thread. A pump serviced from
// inside one of CEF's own nested run loops is not observed, so a pump driven
// purely by those callbacks can latch off permanently and strand every task
// posted with CefPostTask(TID_UI). This scheduler therefore always re-arms a
// bounded heartbeat after a pump, which is what makes the pump self-healing.
class CefPumpScheduler {
 public:
  enum class Action {
    kNone,      // nothing to do
    kRunWork,   // call CefDoMessageLoopWork() now
    kPostWork,  // queue another pump behind the current message
    kArmTimer,  // arm the pump timer for `delay_ms`
  };

  struct Decision {
    Action action = Action::kNone;
    std::int64_t delay_ms = 0;
  };

  // CEF asked for a pump in `delay_ms` milliseconds.
  Decision OnScheduleWork(std::int64_t delay_ms);

  // The armed pump timer elapsed.
  Decision OnTimerElapsed();

  // Call immediately before CefDoMessageLoopWork(). Returns false when the
  // pump is already running: CEF forbids re-entering it, so the caller must
  // skip the call and let EndWork() queue the deferred pump instead.
  bool BeginWork();

  // Call immediately after CefDoMessageLoopWork() returns.
  Decision EndWork();

  bool timer_pending() const { return timer_pending_; }
  bool running() const { return running_; }

  // Forget every pending wake-up; used when the runtime shuts down.
  void Reset();

 private:
  bool running_ = false;
  bool deferred_ = false;
  bool timer_pending_ = false;
};

}  // namespace kelpie::windows
