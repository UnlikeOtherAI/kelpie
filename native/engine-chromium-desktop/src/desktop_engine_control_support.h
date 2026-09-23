#pragma once

// Helpers shared by the DesktopEngine control files (tab lifecycle, page
// operations, trusted input). Internal to the engine; not part of its API.

#include <chrono>
#include <functional>
#include <memory>
#include <string>

#include "desktop_engine_impl.h"

namespace kelpie::engine_control {

struct PendingDevTools {
  CefRefPtr<DesktopDevToolsSession> session;
  std::shared_ptr<DesktopDevToolsSession::Operation> operation;
};

BrowserControlResult DevToolsResult(const DesktopDevToolsSession::Result& result);

DesktopBrowserControl::Timeout RemainingTimeout(std::chrono::steady_clock::time_point started,
                                                DesktopBrowserControl::Timeout timeout);

// Begins `method` on the tab's DevTools session and waits for its reply, giving
// up early when `interrupted` reports that the reply can no longer arrive.
BrowserControlResult RunDevTools(const std::shared_ptr<DesktopEngine::Impl>& impl, TabLease lease,
                                 std::string method, const nlohmann::json& params,
                                 nlohmann::json* output, DesktopBrowserControl::Timeout timeout,
                                 const std::function<bool()>& interrupted = {});

BrowserControlResult DeadlineExceeded();

BrowserControlResult PlannerError(const std::string& code, const std::string& message);

}  // namespace kelpie::engine_control
