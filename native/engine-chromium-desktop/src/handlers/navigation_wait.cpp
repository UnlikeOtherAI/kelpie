#include "navigation_wait.h"

#include <algorithm>
#include <thread>

namespace kelpie {

NavigationWaitResult AwaitNavigation(const DesktopHandlerRuntime& runtime, const TabLease& lease,
                                     std::uint64_t request,
                                     std::chrono::steady_clock::time_point deadline) {
  constexpr auto kPoll = std::chrono::milliseconds(100);
  NavigationWaitResult outcome;
  while (true) {
    const auto now = std::chrono::steady_clock::now();
    if (now >= deadline) {
      outcome.error = ErrorResponse(ErrorCode::kTimeout, "Timed out waiting for navigation to complete");
      return outcome;
    }
    const auto remaining = std::chrono::duration_cast<DesktopBrowserControl::Timeout>(deadline - now);
    BrowserNavigationState state;
    const BrowserControlResult control = RequireBrowserControl(runtime).GetNavigationState(lease, &state, remaining);
    if (!control.ok) {
      outcome.error = ControlError(control);
      return outcome;
    }
    if (state.requested < request) {
      outcome.error = ErrorResponse(ErrorCode::kNavigationError, "The navigation request was replaced");
      return outcome;
    }
    if (!state.error.empty() && state.completed < request) {
      outcome.error = ErrorResponse(ErrorCode::kNavigationError, state.error);
      return outcome;
    }
    if (state.completed >= request) {
      outcome.ok = true;
      outcome.tab = std::move(state.tab);
      return outcome;
    }
    std::this_thread::sleep_for(std::min<std::chrono::steady_clock::duration>(
        kPoll, deadline - std::chrono::steady_clock::now()));
  }
}

}  // namespace kelpie
