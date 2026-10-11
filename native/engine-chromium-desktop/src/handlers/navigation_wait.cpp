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

NavigationWaitResult AwaitOwnedNavigation(const DesktopHandlerRuntime& runtime, TabLease lease,
                                          std::uint64_t request,
                                          const std::string& source_version,
                                          const std::string& destination,
                                          std::chrono::steady_clock::time_point deadline) {
  constexpr auto kPoll = std::chrono::milliseconds(100);
  lease.document_version.reset();
  std::optional<std::string> transitioned_version;
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
    if (state.requested != request) {
      outcome.error = ErrorResponse(ErrorCode::kNavigationError, "The navigation request was replaced");
      return outcome;
    }
    if (state.tab.document_version != source_version) {
      if (state.tab.url != destination ||
          (transitioned_version && state.tab.document_version != *transitioned_version)) {
        outcome.error = ErrorResponse(ErrorCode::kNavigationError, "The destination document changed during navigation");
        return outcome;
      }
      transitioned_version = state.tab.document_version;
    }
    if (!state.error.empty() && state.completed < request) {
      outcome.error = ErrorResponse(ErrorCode::kNavigationError, state.error);
      return outcome;
    }
    if (state.completed >= request) {
      if (!transitioned_version) {
        outcome.error = ErrorResponse(ErrorCode::kNavigationError, "Navigation completed without a document transition");
        return outcome;
      }
      outcome.ok = true;
      outcome.tab = std::move(state.tab);
      return outcome;
    }
    std::this_thread::sleep_for(std::min<std::chrono::steady_clock::duration>(
        kPoll, deadline - std::chrono::steady_clock::now()));
  }
}

}  // namespace kelpie
