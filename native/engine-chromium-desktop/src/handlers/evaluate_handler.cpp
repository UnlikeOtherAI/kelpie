#include "evaluate_handler.h"

namespace kelpie {

EvaluateHandler::EvaluateHandler(DesktopHandlerRuntime runtime)
    : runtime_(std::move(runtime)) {}

void EvaluateHandler::Register(DesktopRouter& router) const {
  router.Register("evaluate", [this](const nlohmann::json& params) { return Evaluate(params); });
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

}  // namespace kelpie
