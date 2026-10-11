#include "navigation_wait.h"

#include <algorithm>
#include <cctype>
#include <thread>

namespace kelpie {
namespace {

std::string NormalizeUrl(std::string url) {
  const auto scheme_end = url.find("://");
  if (scheme_end == std::string::npos) return url;
  std::transform(url.begin(), url.begin() + static_cast<std::ptrdiff_t>(scheme_end), url.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  const auto authority_begin = scheme_end + 3;
  const auto authority_end = url.find_first_of("/?#", authority_begin);
  const auto end = authority_end == std::string::npos ? url.size() : authority_end;
  std::transform(url.begin() + static_cast<std::ptrdiff_t>(authority_begin),
                 url.begin() + static_cast<std::ptrdiff_t>(end),
                 url.begin() + static_cast<std::ptrdiff_t>(authority_begin),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  auto authority = url.substr(authority_begin, end - authority_begin);
  const auto scheme = url.substr(0, scheme_end);
  if ((scheme == "https" && authority.ends_with(":443")) ||
      (scheme == "http" && authority.ends_with(":80"))) {
    authority.erase(authority.rfind(':'));
  }
  auto suffix = authority_end == std::string::npos ? std::string() : url.substr(authority_end);
  if (suffix.empty()) suffix = "/";
  if (suffix == "/") suffix.clear();
  return scheme + "://" + authority + suffix;
}

}  // namespace

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
      if (NormalizeUrl(state.tab.url) != NormalizeUrl(destination) ||
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
