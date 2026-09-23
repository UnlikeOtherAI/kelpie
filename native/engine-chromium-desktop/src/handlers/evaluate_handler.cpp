#include "evaluate_handler.h"

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
    TabLease lease;
    BrowserControlResult result = RequireBrowserControl(runtime_).ResolveTab(
        OptionalTabId(params), OptionalGeneration(params), &lease, ControlTimeout(params));
    if (!result.ok) return ControlError(result);
    // A caller's script can navigate (`location.href = ...`, a form submit), so
    // it moves the wait-for-navigation baseline like any other action. Kelpie's
    // own internal evaluations do not come through here and leave it alone.
    result = RequireBrowserControl(runtime_).MarkNavigationAction(lease, ControlTimeout(params));
    if (!result.ok) return ControlError(result);
    nlohmann::json value;
    result = RequireBrowserControl(runtime_).Evaluate(lease, expression, &value, ControlTimeout(params));
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
  const int poll_ms = 100;
  const auto deadline = std::chrono::steady_clock::now() + timeout;
  try {
    TabLease lease;
    BrowserControlResult resolved = RequireBrowserControl(runtime_).ResolveTab(
        OptionalTabId(params), OptionalGeneration(params), &lease, timeout);
    if (!resolved.ok) return ControlError(resolved);
    BrowserNavigationState initial;
    resolved = RequireBrowserControl(runtime_).GetNavigationState(lease, &initial, timeout);
    if (!resolved.ok) return ControlError(resolved);
    // The navigation to wait for is the first one after the tab's most recent
    // navigation-capable action, whether the API or the page started it. The
    // baseline is read once, so the wait's own polling cannot move it.
    const std::uint64_t baseline = initial.navigation.baseline;
    NavigationTracker::Progress progress = initial.navigation.Since(baseline);
    while (true) {
      const auto now = std::chrono::steady_clock::now();
      if (now >= deadline) {
        return ErrorResponse(ErrorCode::kTimeout,
            progress == NavigationTracker::Progress::kNotStarted
                ? "No navigation started within " + std::to_string(timeout.count()) + " ms"
                : "Timed out waiting for navigation to complete");
      }
      const auto remaining = std::chrono::duration_cast<DesktopBrowserControl::Timeout>(deadline - now);
      BrowserNavigationState state;
      const BrowserControlResult control = RequireBrowserControl(runtime_).GetNavigationState(
          lease, &state, remaining);
      // The last poll only has what is left of the wait. When the wait's own
      // deadline cut it short, the answer is the wait's timeout, which says
      // whether a navigation had started, not a generic operation timeout.
      if (!control.ok && control.error_code == "TIMEOUT" && std::chrono::steady_clock::now() >= deadline) continue;
      if (!control.ok) return ControlError(control);
      progress = state.navigation.Since(baseline);
      if (progress == NavigationTracker::Progress::kFailed) {
        return ErrorResponse(ErrorCode::kNavigationError, state.navigation.error);
      }
      if (progress == NavigationTracker::Progress::kFinished) {
        return SuccessResponse({{"tab", TabJson(state.tab)}});
      }
      std::this_thread::sleep_for(std::min(std::chrono::milliseconds(poll_ms),
          std::chrono::duration_cast<std::chrono::milliseconds>(deadline - std::chrono::steady_clock::now())));
    }
  } catch (const std::invalid_argument& exception) { return InvalidParams(exception.what()); }
}

}  // namespace kelpie
