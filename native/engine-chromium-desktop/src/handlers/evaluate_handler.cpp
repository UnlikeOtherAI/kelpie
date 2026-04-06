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
    HandlerContext& context = RequireHandlerContext(runtime_);
    const std::string expression = RequireString(params, "expression");
    return SuccessResponse({{"result", context.EvaluateJsReturningJson(expression)}});
  } catch (const std::invalid_argument& exception) {
    return InvalidParams(exception.what());
  }
}

nlohmann::json EvaluateHandler::WaitForElement(const nlohmann::json& params) const {
  try {
    HandlerContext& context = RequireHandlerContext(runtime_);
    const std::string selector = RequireString(params, "selector");
    const int timeout_ms = 5000;
    const int poll_ms = 100;
    const std::int64_t started = NowMillis();
    const std::string script =
        "(() => { const el = document.querySelector(" + JsStringLiteral(selector) + ");"
        "return {found: !!el}; })()";
    while (true) {
      const nlohmann::json result = context.EvaluateJsReturningJson(script);
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
  HandlerContext& context = RequireHandlerContext(runtime_);
  const int timeout_ms = 10000;
  const int poll_ms = 100;
  const std::int64_t started = NowMillis();
  while (context.Renderer()->IsLoading()) {
    if ((NowMillis() - started) >= timeout_ms) {
      return ErrorResponse(ErrorCode::kTimeout, "Timed out waiting for navigation to complete");
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(poll_ms));
  }
  return SuccessResponse({
      {"url", context.Renderer()->CurrentUrl()},
      {"title", context.Renderer()->CurrentTitle()},
  });
}

}  // namespace kelpie
