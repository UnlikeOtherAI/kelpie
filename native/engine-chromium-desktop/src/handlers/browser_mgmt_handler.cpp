#include "browser_mgmt_handler.h"

namespace kelpie {

BrowserManagementHandler::BrowserManagementHandler(DesktopHandlerRuntime runtime) : runtime_(std::move(runtime)) {}

void BrowserManagementHandler::Register(DesktopRouter& router) const {
  router.Register("get-tabs", [this](const nlohmann::json& params) { return GetTabs(params); });
  router.Register("new-tab", [this](const nlohmann::json& params) { return NewTab(params); });
  router.Register("switch-tab", [this](const nlohmann::json& params) { return SwitchTab(params); });
  router.Register("close-tab", [this](const nlohmann::json& params) { return CloseTab(params); });
}

nlohmann::json BrowserManagementHandler::GetTabs(const nlohmann::json& params) const {
  std::vector<TabSnapshot> tabs;
  const auto result = RequireBrowserControl(runtime_).GetTabs(&tabs, ControlTimeout(params));
  if (!result.ok) return ControlError(result);
  nlohmann::json response = nlohmann::json::array();
  for (const TabSnapshot& tab : tabs) response.push_back(TabJson(tab));
  return SuccessResponse({{"tabs", response}, {"count", response.size()}});
}

nlohmann::json BrowserManagementHandler::NewTab(const nlohmann::json& params) const {
  try {
    const auto url = params.find("url");
    if (url != params.end() && (!url->is_string() || url->get<std::string>().empty())) return InvalidParams("url must be a non-empty string");
    NewTabRequest request;
    request.url = url == params.end() ? std::string() : url->get<std::string>();
    if (const auto invalid = ReadPartitionFields(params, &request)) return *invalid;
    TabSnapshot tab;
    const auto result = RequireBrowserControl(runtime_).CreateTab(request, &tab, ControlTimeout(params));
    if (!result.ok) return ControlError(result);
    return SuccessResponse({{"tab", TabJson(tab)}, {"tabId", tab.id}});
  } catch (const std::invalid_argument& exception) { return InvalidParams(exception.what()); }
}

nlohmann::json BrowserManagementHandler::SwitchTab(const nlohmann::json& params) const {
  try {
    TabLease lease;
    const auto resolved = RequireBrowserControl(runtime_).ResolveTab(OptionalTabId(params), OptionalGeneration(params), &lease, ControlTimeout(params));
    if (!resolved.ok) return ControlError(resolved);
    const auto result = RequireBrowserControl(runtime_).ActivateTab(lease, ControlTimeout(params));
    if (!result.ok) return ControlError(result);
    return SuccessResponse({{"tab", result.tab ? TabJson(*result.tab) : nlohmann::json::object()}});
  } catch (const std::invalid_argument& exception) { return InvalidParams(exception.what()); }
}

nlohmann::json BrowserManagementHandler::CloseTab(const nlohmann::json& params) const {
  try {
    TabLease lease;
    const auto resolved = RequireBrowserControl(runtime_).ResolveTab(OptionalTabId(params), OptionalGeneration(params), &lease, ControlTimeout(params));
    if (!resolved.ok) return ControlError(resolved);
    const auto result = RequireBrowserControl(runtime_).CloseTab(lease, ControlTimeout(params));
    if (!result.ok) return ControlError(result);
    return SuccessResponse({{"tab", result.tab ? TabJson(*result.tab) : nlohmann::json::object()}, {"closedTabId", lease.id}});
  } catch (const std::invalid_argument& exception) { return InvalidParams(exception.what()); }
}

}  // namespace kelpie
