#include "interaction_handler.h"

namespace kelpie {
namespace {

nlohmann::json Dispatch(const DesktopHandlerRuntime& runtime, const nlohmann::json& params,
                        nlohmann::json input) {
  try {
    TabLease lease;
    auto result = RequireBrowserControl(runtime).ResolveTab(OptionalTabId(params), OptionalGeneration(params), &lease,
                                                            ControlTimeout(params));
    if (!result.ok) return ControlError(result);
    nlohmann::json output;
    result = RequireBrowserControl(runtime).DispatchTrustedInput(lease, std::move(input), &output, ControlTimeout(params));
    if (!result.ok) return ControlError(result);
    return SuccessResponse({{"tab", result.tab ? TabJson(*result.tab) : nlohmann::json::object()},
                            {"input", output}});
  } catch (const std::invalid_argument& error) { return InvalidParams(error.what()); }
}

}  // namespace

InteractionHandler::InteractionHandler(DesktopHandlerRuntime runtime) : runtime_(std::move(runtime)) {}

void InteractionHandler::Register(DesktopRouter& router) const {
  router.Register("click", [this](const nlohmann::json& params) { return Click(params); });
  router.Register("fill", [this](const nlohmann::json& params) { return Fill(params); });
  router.Register("type", [this](const nlohmann::json& params) { return Type(params); });
  router.Register("select-option", [this](const nlohmann::json& params) { return SelectOption(params); });
  router.Register("check", [this](const nlohmann::json& params) { return Check(params, true); });
  router.Register("uncheck", [this](const nlohmann::json& params) { return Check(params, false); });
  router.Register("press-key", [this](const nlohmann::json& params) { return PressKey(params); });
}

nlohmann::json InteractionHandler::Click(const nlohmann::json& params) const {
  try { return Dispatch(runtime_, params, {{"type", "click"}, {"selector", RequireString(params, "selector")}}); }
  catch (const std::invalid_argument& error) { return InvalidParams(error.what()); }
}
nlohmann::json InteractionHandler::Fill(const nlohmann::json& params) const {
  try { return Dispatch(runtime_, params, {{"type", "fill"}, {"selector", RequireString(params, "selector")}, {"value", RequireString(params, "value", true)}}); }
  catch (const std::invalid_argument& error) { return InvalidParams(error.what()); }
}
nlohmann::json InteractionHandler::Type(const nlohmann::json& params) const {
  try { nlohmann::json input = {{"type", "type"}, {"text", RequireString(params, "text", true)}};
    if (params.contains("selector")) input["selector"] = RequireString(params, "selector");
    return Dispatch(runtime_, params, std::move(input)); }
  catch (const std::invalid_argument& error) { return InvalidParams(error.what()); }
}
nlohmann::json InteractionHandler::SelectOption(const nlohmann::json& params) const {
  try { return Dispatch(runtime_, params, {{"type", "selectOption"}, {"selector", RequireString(params, "selector")}, {"value", RequireString(params, "value")}}); }
  catch (const std::invalid_argument& error) { return InvalidParams(error.what()); }
}
nlohmann::json InteractionHandler::Check(const nlohmann::json& params, bool checked) const {
  try { return Dispatch(runtime_, params, {{"type", "setChecked"}, {"selector", RequireString(params, "selector")}, {"checked", checked}}); }
  catch (const std::invalid_argument& error) { return InvalidParams(error.what()); }
}
nlohmann::json InteractionHandler::PressKey(const nlohmann::json& params) const {
  try { nlohmann::json input = {{"type", "key"}, {"key", RequireString(params, "key")}};
    for (const char* key : {"code", "modifiers"}) if (params.contains(key)) input[key] = params[key];
    return Dispatch(runtime_, params, std::move(input)); }
  catch (const std::invalid_argument& error) { return InvalidParams(error.what()); }
}

}  // namespace kelpie
