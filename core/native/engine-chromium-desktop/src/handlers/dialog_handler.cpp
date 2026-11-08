#include "dialog_handler.h"
namespace kelpie {
void DialogHandler::Register(DesktopRouter& router) const {
  router.Register("get-dialog", [this](const nlohmann::json& p) { return Get(p); });
  router.Register("handle-dialog", [this](const nlohmann::json& p) { return Handle(p); });
}
nlohmann::json DialogHandler::Get(const nlohmann::json& params) const {
  try {
    TabLease lease; auto result = RequireBrowserControl(runtime_).ResolveTab(OptionalTabId(params), OptionalGeneration(params), &lease, ControlTimeout(params));
    if (!result.ok) return ControlError(result);
    nlohmann::json dialog; result = RequireBrowserControl(runtime_).GetDialog(lease, &dialog, ControlTimeout(params));
    if (!result.ok) return ControlError(result);
    nlohmann::json body = dialog; if (result.tab) body["tab"] = TabJson(*result.tab); return SuccessResponse(body);
  } catch (const std::invalid_argument& e) { return InvalidParams(e.what()); }
}
nlohmann::json DialogHandler::Handle(const nlohmann::json& params) const {
  try {
    const std::string action = RequireString(params, "action");
    if (action != "accept" && action != "dismiss") return InvalidParams("action must be accept or dismiss");
    if (params.contains("promptText") && !params["promptText"].is_string()) return InvalidParams("promptText must be a string");
    TabLease lease; auto result = RequireBrowserControl(runtime_).ResolveTab(OptionalTabId(params), OptionalGeneration(params), &lease, ControlTimeout(params));
    if (!result.ok) return ControlError(result);
    nlohmann::json output; result = RequireBrowserControl(runtime_).HandleDialog(lease, params, &output, ControlTimeout(params));
    if (!result.ok) return ControlError(result);
    nlohmann::json body = output; if (result.tab) body["tab"] = TabJson(*result.tab); return SuccessResponse(body);
  } catch (const std::invalid_argument& e) { return InvalidParams(e.what()); }
}
}  // namespace kelpie
