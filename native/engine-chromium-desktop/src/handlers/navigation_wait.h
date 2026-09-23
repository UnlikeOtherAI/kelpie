#pragma once

#include <chrono>

#include "handler_support.h"

namespace kelpie {

struct NavigationWaitResult {
  bool ok = false;
  TabSnapshot tab;
  // The error response to send when `ok` is false.
  nlohmann::json error;
};

// Polls the tab until the first main-frame navigation after `initial`'s
// baseline -- the tab's most recent navigation-capable action, whether the API
// or the page started what followed it -- finishes loading or fails, or
// `deadline` passes. The baseline is taken from `initial` once, so the wait's
// own polling cannot move it. `budget` is the caller's whole timeout, which
// the error names when no navigation started at all.
NavigationWaitResult AwaitNavigation(const DesktopHandlerRuntime& runtime, const TabLease& lease,
                                     const NavigationTracker& initial,
                                     std::chrono::steady_clock::time_point deadline,
                                     DesktopBrowserControl::Timeout budget);

}  // namespace kelpie
