#include "desktop_engine_control_support.h"

#include "include/cef_parser.h"
#include "kelpie/internal_scheme.h"

namespace kelpie::engine_control {

BrowserControlResult DevToolsResult(const DesktopDevToolsSession::Result& result) {
  BrowserControlResult output = result.ok ? BrowserControlResult::Success()
                                         : BrowserControlResult::Failure(result.error_code, result.message);
  output.operation_may_have_completed = result.operation_may_have_completed;
  return output;
}

DesktopBrowserControl::Timeout RemainingTimeout(std::chrono::steady_clock::time_point started,
                                                DesktopBrowserControl::Timeout timeout) {
  const auto elapsed = std::chrono::duration_cast<DesktopBrowserControl::Timeout>(
      std::chrono::steady_clock::now() - started);
  return elapsed >= timeout ? DesktopBrowserControl::Timeout::zero() : timeout - elapsed;
}

BrowserControlResult RunDevTools(const std::shared_ptr<DesktopEngine::Impl>& impl, TabLease lease,
                                 std::string method, const nlohmann::json& params,
                                 nlohmann::json* output, DesktopBrowserControl::Timeout timeout,
                                 const std::function<bool()>& interrupted) {
  if (!output) return BrowserControlResult::Failure("INTERNAL", "result is required");
  const auto started_at = std::chrono::steady_clock::now();
  auto pending = std::make_shared<PendingDevTools>();
  const auto started = impl->RunOnUi([impl, lease, method = std::move(method), params, pending] {
    auto* tab = impl->FindTab(lease);
    if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist or is stale");
    pending->session = tab->devtools;
    pending->operation = pending->session->Begin(tab->browser, method, params);
    return BrowserControlResult::Success(impl->Snapshot(*tab));
  }, timeout);
  if (!started.ok) return started;
  const auto completed =
      pending->session->Wait(pending->operation, RemainingTimeout(started_at, timeout), interrupted);
  const auto result = DevToolsResult(completed);
  if (result.ok) *output = completed.value;
  return result;
}

BrowserControlResult DeadlineExceeded() {
  return BrowserControlResult::Failure("TIMEOUT", "Browser operation timed out before the next native operation");
}

BrowserControlResult PlannerError(const std::string& code, const std::string& message) {
  return BrowserControlResult::Failure(code.empty() ? "INVALID_PARAMS" : code, message);
}

bool IsNavigableUrl(const std::string& url) {
  if (url.empty()) return false;
  CefURLParts parts;
  // `kelpie://` is checked explicitly: CefParseURL only recognises a custom
  // scheme once Chromium has been initialised in this process, and the shell
  // creates the start page tab through the same validator.
  return CefParseURL(url, parts) || IsInternalSchemeUrl(url) ||
         url.rfind("about:", 0) == 0 || url.rfind("data:", 0) == 0;
}

}  // namespace kelpie::engine_control
