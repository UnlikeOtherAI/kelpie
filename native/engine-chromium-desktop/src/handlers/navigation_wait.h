#pragma once

#include <chrono>
#include <cstdint>

#include "handler_support.h"

namespace kelpie {

struct NavigationWaitResult {
  bool ok = false;
  TabSnapshot tab;
  // The error response to send when `ok` is false.
  nlohmann::json error;
};

// Polls the tab until navigation request number `request` finishes loading,
// fails, is replaced by a newer request, or `deadline` passes.
NavigationWaitResult AwaitNavigation(const DesktopHandlerRuntime& runtime, const TabLease& lease,
                                     std::uint64_t request,
                                     std::chrono::steady_clock::time_point deadline);

}  // namespace kelpie
