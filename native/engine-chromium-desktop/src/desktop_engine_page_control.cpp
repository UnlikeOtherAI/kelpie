// DesktopEngine page operations that go through the tab's DevTools session:
// JavaScript evaluation, screenshots, cookies and the raw passthrough.
#include "desktop_engine_control_support.h"

#include <chrono>
#include <memory>
#include <utility>

#include "desktop_cookie_planner.h"

namespace kelpie {

using namespace engine_control;

BrowserControlResult DesktopEngine::Evaluate(TabLease lease, std::string script, Json* value, Timeout timeout) {
  const auto impl = impl_;
  if (value == nullptr) return BrowserControlResult::Failure("INTERNAL", "result is required");
  const auto started_at = std::chrono::steady_clock::now();
  auto pending = std::make_shared<PendingDevTools>();
  const auto started = impl->RunOnUi([impl, lease, script = std::move(script), pending] {
    auto* tab = impl->FindTab(lease);
    if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist or is stale");
    pending->session = tab->devtools;
    pending->operation = pending->session->Begin(tab->browser, "Runtime.evaluate",
                                                  DesktopDevToolsSession::EvaluateParams(script));
    return BrowserControlResult::Success(impl->Snapshot(*tab));
  }, timeout);
  if (!started.ok) return started;
  const auto parsed = DesktopDevToolsSession::ParseEvaluateResult(
      pending->session->Wait(pending->operation, RemainingTimeout(started_at, timeout)));
  const auto result = DevToolsResult(parsed);
  if (result.ok) *value = parsed.value;
  return result;
}

BrowserControlResult DesktopEngine::Screenshot(TabLease lease, BrowserScreenshot* image, Timeout timeout) {
  const auto impl = impl_;
  if (image == nullptr) return BrowserControlResult::Failure("INTERNAL", "image is required");
  const auto screenshot_params = DesktopDevToolsSession::ScreenshotParams(Json::object());
  if (!screenshot_params) return BrowserControlResult::Failure("INTERNAL", "Screenshot parameters are invalid");
  const auto started_at = std::chrono::steady_clock::now();
  auto pending = std::make_shared<PendingDevTools>();
  const auto started = impl->RunOnUi([impl, lease, pending, screenshot_params] {
    auto* tab = impl->FindTab(lease);
    if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist or is stale");
    pending->session = tab->devtools;
    pending->operation = pending->session->Begin(tab->browser, "Page.captureScreenshot",
                                                  *screenshot_params);
    return BrowserControlResult::Success(impl->Snapshot(*tab));
  }, timeout);
  if (!started.ok) return started;
  const auto parsed = DesktopDevToolsSession::ParseScreenshotResult(
      pending->session->Wait(pending->operation, RemainingTimeout(started_at, timeout)));
  const auto result = DevToolsResult(parsed);
  if (result.ok) {
    image->mime_type = parsed.value.value("mimeType", "image/png");
    image->base64_data = parsed.value.value("data", "");
  }
  return result;
}
BrowserControlResult DesktopEngine::GetCookies(TabLease lease, const Json& query, Json* cookies, Timeout timeout) {
  if (!cookies) return BrowserControlResult::Failure("INTERNAL", "cookies is required");
  const auto planned = desktop_cookie::PlanGetCookies(query);
  if (!planned.ok) return PlannerError("INVALID_PARAMS", planned.error);
  Json response;
  const std::string method = query.contains("url") ? "Network.getCookies" : "Network.getAllCookies";
  const auto result = DevTools(lease, method, planned.params, &response, timeout);
  if (!result.ok) return result;
  const auto listed = response.find("cookies");
  if (listed == response.end() || !listed->is_array()) {
    return BrowserControlResult::Failure("CDP_MALFORMED_RESULT", method + " did not return cookies");
  }
  Json filtered = Json::array();
  for (const auto& cookie : *listed) if (desktop_cookie::MatchesFilter(cookie, query)) filtered.push_back(cookie);
  *cookies = std::move(filtered);
  return result;
}

BrowserControlResult DesktopEngine::SetCookies(TabLease lease, const Json& cookies, Json* output, Timeout timeout) {
  const Json values = cookies.is_array() ? cookies : Json::array({cookies});
  if (values.empty()) return BrowserControlResult::Failure("INVALID_PARAMS", "At least one cookie is required");
  const auto started_at = std::chrono::steady_clock::now();
  std::size_t set = 0;
  for (const auto& value : values) {
    const auto planned = desktop_cookie::PlanSetCookie(value);
    if (!planned.ok) return PlannerError("INVALID_PARAMS", planned.error);
    const auto remaining = RemainingTimeout(started_at, timeout);
    if (remaining <= Timeout::zero()) return DeadlineExceeded();
    Json response;
    const auto result = DevTools(lease, "Network.setCookie", planned.params, &response, remaining);
    if (!result.ok) return result;
    const auto success = response.find("success");
    if (success == response.end() || !success->is_boolean() || !success->get<bool>()) {
      return BrowserControlResult::Failure("DEVTOOLS_ERROR", "Chromium rejected the cookie");
    }
    ++set;
  }
  if (output) *output = {{"set", set}};
  return BrowserControlResult::Success();
}

BrowserControlResult DesktopEngine::DeleteCookies(TabLease lease, const Json& query, Json* output, Timeout timeout) {
  const auto planned = desktop_cookie::PlanDeleteCookies(query);
  if (!planned.ok) return PlannerError("INVALID_PARAMS", planned.error);
  const auto started_at = std::chrono::steady_clock::now();
  const auto remaining = RemainingTimeout(started_at, timeout);
  if (remaining <= Timeout::zero()) return DeadlineExceeded();
  Json response;
  const std::string method = planned.action == desktop_cookie::DeletePlan::Action::kClearAll
      ? "Network.clearBrowserCookies" : "Network.deleteCookies";
  const auto result = DevTools(lease, method, planned.params, &response, remaining);
  if (result.ok && output) *output = std::move(response);
  return result;
}

BrowserControlResult DesktopEngine::DevTools(TabLease lease, std::string method, const Json& params,
                                             Json* output, Timeout timeout) {
  return RunDevTools(impl_, lease, std::move(method), params, output, timeout);
}

}  // namespace kelpie
