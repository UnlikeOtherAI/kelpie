#include "evaluate_handler.h"

#include "navigation_wait.h"

#include <algorithm>
#include <chrono>
#include <thread>

namespace kelpie {

EvaluateHandler::EvaluateHandler(DesktopHandlerRuntime runtime)
    : runtime_(std::move(runtime)) {}

void EvaluateHandler::Register(DesktopRouter& router) const {
  router.Register("evaluate", [this](const nlohmann::json& params) { return Evaluate(params); });
  router.Register("wait-for-element",
                  [this](const nlohmann::json& params) { return WaitForElement(params); });
  router.Register("wait-for-navigation",
                  [this](const nlohmann::json& params) { return WaitForNavigation(params); });
}

nlohmann::json EvaluateHandler::Evaluate(const nlohmann::json& params) const {
  try {
    const std::string expression = RequireString(params, "expression");
    nlohmann::json value;
    const BrowserControlResult result = EvaluateForTab(runtime_, params, expression, &value);
    if (!result.ok) return ControlError(result);
    return SuccessResponse({{"result", value}, {"tab", result.tab ? TabJson(*result.tab) : nlohmann::json::object()}});
  } catch (const std::invalid_argument& exception) {
    return InvalidParams(exception.what());
  }
}

nlohmann::json EvaluateHandler::WaitForElement(const nlohmann::json& params) const {
  try {
    const std::string selector = RequireString(params, "selector");
    const auto timeout = ControlTimeout(params);
    const std::string state = params.value("state", std::string("visible"));
    if (state != "attached" && state != "visible" && state != "hidden") {
      return InvalidParams("state must be attached, visible, or hidden");
    }
    const int poll_ms = 100;
    const auto deadline = std::chrono::steady_clock::now() + timeout;
    const std::string script =
        "(() => { const el = document.querySelector(" + JsStringLiteral(selector) + ");"
        "if (!el) return {attached:false,visible:false}; const style=getComputedStyle(el);"
        "const rect=el.getBoundingClientRect(); return {attached:true,visible:style.display !== 'none' && "
        "style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0}; })()";
    TabLease lease;
    BrowserControlResult resolved = RequireBrowserControl(runtime_).ResolveTab(
        OptionalTabId(params), OptionalGeneration(params), &lease, ControlTimeout(params));
    if (!resolved.ok) return ControlError(resolved);
    while (true) {
      const auto now = std::chrono::steady_clock::now();
      if (now >= deadline) {
        return ErrorResponse(ErrorCode::kTimeout, "Timed out waiting for element '" + selector + "'");
      }
      const auto remaining = std::chrono::duration_cast<DesktopBrowserControl::Timeout>(deadline - now);
      nlohmann::json result;
      const BrowserControlResult control = RequireBrowserControl(runtime_).Evaluate(
          lease, script, &result, remaining);
      if (!control.ok) return ControlError(control);
      const bool attached = result.value("attached", result.value("found", false));
      const bool visible = result.value("visible", attached);
      const bool matched = state == "attached" ? attached : state == "visible" ? visible : !visible;
      if (matched) {
        return SuccessResponse({{"selector", selector}, {"state", state}});
      }
      std::this_thread::sleep_for(std::min(std::chrono::milliseconds(poll_ms),
          std::chrono::duration_cast<std::chrono::milliseconds>(deadline - std::chrono::steady_clock::now())));
    }
  } catch (const std::invalid_argument& exception) {
    return InvalidParams(exception.what());
  }
}

nlohmann::json EvaluateHandler::WaitForNavigation(const nlohmann::json& params) const {
  const auto timeout = ControlTimeout(params);
  const auto deadline = std::chrono::steady_clock::now() + timeout;
  try {
    TabLease lease;
    BrowserControlResult resolved = RequireBrowserControl(runtime_).ResolveTab(
        OptionalTabId(params), OptionalGeneration(params), &lease, timeout);
    if (!resolved.ok) return ControlError(resolved);
    BrowserNavigationState initial;
    resolved = RequireBrowserControl(runtime_).GetNavigationState(lease, &initial, timeout);
    if (!resolved.ok) return ControlError(resolved);
    if (initial.requested == 0) return ErrorResponse(ErrorCode::kNavigationError, "No navigation has been requested");
    const NavigationWaitResult waited = AwaitNavigation(runtime_, lease, initial.requested, deadline);
    if (!waited.ok) return waited.error;
    return SuccessResponse({{"tab", TabJson(waited.tab)}});
  } catch (const std::invalid_argument& exception) { return InvalidParams(exception.what()); }
}

}  // namespace kelpie
