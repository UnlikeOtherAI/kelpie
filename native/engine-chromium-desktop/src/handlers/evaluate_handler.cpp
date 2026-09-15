#include "evaluate_handler.h"

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
    const int timeout_ms = static_cast<int>(ControlTimeout(params).count());
    const int poll_ms = 100;
    const std::int64_t started = NowMillis();
    const std::string script =
        "(() => { const el = document.querySelector(" + JsStringLiteral(selector) + ");"
        "return {found: !!el}; })()";
    TabLease lease;
    BrowserControlResult resolved = RequireBrowserControl(runtime_).ResolveTab(
        OptionalTabId(params), OptionalGeneration(params), &lease, ControlTimeout(params));
    if (!resolved.ok) return ControlError(resolved);
    while (true) {
      nlohmann::json result;
      const BrowserControlResult control = RequireBrowserControl(runtime_).Evaluate(
          lease, script, &result, ControlTimeout(params));
      if (!control.ok) return ControlError(control);
      if (result.value("found", false)) {
        return SuccessResponse({{"selector", selector}});
      }
      if ((NowMillis() - started) >= timeout_ms) {
        return ErrorResponse(ErrorCode::kTimeout,
                             "Timed out waiting for element '" + selector + "'");
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(poll_ms));
    }
  } catch (const std::invalid_argument& exception) {
    return InvalidParams(exception.what());
  }
}

nlohmann::json EvaluateHandler::WaitForNavigation(const nlohmann::json& params) const {
  const int timeout_ms = static_cast<int>(ControlTimeout(params).count());
  const int poll_ms = 100;
  const std::int64_t started = NowMillis();
  try {
    TabLease lease;
    BrowserControlResult resolved = RequireBrowserControl(runtime_).ResolveTab(
        OptionalTabId(params), OptionalGeneration(params), &lease, ControlTimeout(params));
    if (!resolved.ok) return ControlError(resolved);
    while (true) {
      nlohmann::json ready_state;
      const BrowserControlResult control = RequireBrowserControl(runtime_).Evaluate(
          lease, "document.readyState", &ready_state, ControlTimeout(params));
      if (!control.ok) return ControlError(control);
      if (ready_state.is_string() && ready_state.get<std::string>() == "complete") {
        return SuccessResponse({{"tab", control.tab ? TabJson(*control.tab) : nlohmann::json::object()}});
      }
    if ((NowMillis() - started) >= timeout_ms) {
      return ErrorResponse(ErrorCode::kTimeout, "Timed out waiting for navigation to complete");
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(poll_ms));
  }
  } catch (const std::invalid_argument& exception) { return InvalidParams(exception.what()); }
}

}  // namespace kelpie
