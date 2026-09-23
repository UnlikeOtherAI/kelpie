#include "navigation_wait.h"

#include <algorithm>
#include <string>
#include <thread>

namespace kelpie {
namespace {

constexpr auto kPoll = std::chrono::milliseconds(100);

// The least time a poll is given to be answered by the UI thread, however
// little of the wait is left.
constexpr DesktopBrowserControl::Timeout kPollFloor{50};

}  // namespace

NavigationWaitResult AwaitNavigation(const DesktopHandlerRuntime& runtime, const TabLease& lease,
                                     const NavigationTracker& initial,
                                     std::chrono::steady_clock::time_point deadline,
                                     DesktopBrowserControl::Timeout budget) {
  const std::uint64_t baseline = initial.baseline;
  NavigationTracker::Progress progress = initial.Since(baseline);
  NavigationWaitResult outcome;
  while (true) {
    const auto now = std::chrono::steady_clock::now();
    if (now >= deadline) {
      outcome.error = ErrorResponse(ErrorCode::kTimeout,
          progress == NavigationTracker::Progress::kNotStarted
              ? "No navigation started within " + std::to_string(budget.count()) + " ms"
              : "Timed out waiting for navigation to complete");
      return outcome;
    }
    // A poll gets what is left of the wait, rounded up and never less than
    // kPollFloor. Truncating 1.9 ms to 1 (or 0) gave the last poll no time to
    // be answered and made it time out just short of the deadline.
    const auto remaining = std::max(
        std::chrono::ceil<DesktopBrowserControl::Timeout>(deadline - now), kPollFloor);
    BrowserNavigationState state;
    const BrowserControlResult control = RequireBrowserControl(runtime).GetNavigationState(lease, &state, remaining);
    // So a poll that times out has run past the wait's deadline, and the answer
    // is the wait's own timeout, which says whether a navigation had started,
    // not a generic "Browser operation timed out".
    if (!control.ok && control.error_code == "TIMEOUT" && std::chrono::steady_clock::now() >= deadline) continue;
    if (!control.ok) {
      outcome.error = ControlError(control);
      return outcome;
    }
    progress = state.navigation.Since(baseline);
    if (progress == NavigationTracker::Progress::kFailed) {
      outcome.error = ErrorResponse(ErrorCode::kNavigationError, state.navigation.error);
      return outcome;
    }
    if (progress == NavigationTracker::Progress::kFinished) {
      outcome.ok = true;
      outcome.tab = std::move(state.tab);
      return outcome;
    }
    std::this_thread::sleep_for(std::min<std::chrono::steady_clock::duration>(
        kPoll, deadline - std::chrono::steady_clock::now()));
  }
}

}  // namespace kelpie
