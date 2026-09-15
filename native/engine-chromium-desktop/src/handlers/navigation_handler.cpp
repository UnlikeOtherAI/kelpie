#include "navigation_handler.h"

namespace kelpie {
namespace {

BrowserControlResult Resolve(const DesktopHandlerRuntime& runtime, const nlohmann::json& params,
                             TabLease* lease) {
  return RequireBrowserControl(runtime).ResolveTab(OptionalTabId(params), OptionalGeneration(params), lease,
                                                    ControlTimeout(params));
}

nlohmann::json SnapshotResponse(const BrowserControlResult& result, const TabSnapshot& tab) {
  if (!result.ok) return ControlError(result);
  return SuccessResponse({{"tab", TabJson(tab)}, {"url", tab.url}, {"title", tab.title}});
}

}  // namespace

NavigationHandler::NavigationHandler(DesktopHandlerRuntime runtime) : runtime_(std::move(runtime)) {}

void NavigationHandler::Register(DesktopRouter& router) const {
  router.Register("navigate", [this](const nlohmann::json& params) { return Navigate(params); });
  router.Register("back", [this](const nlohmann::json& params) { return Back(params); });
  router.Register("forward", [this](const nlohmann::json& params) { return Forward(params); });
  router.Register("reload", [this](const nlohmann::json& params) { return Reload(params); });
  router.Register("get-current-url", [this](const nlohmann::json& params) { return GetCurrentUrl(params); });
}

nlohmann::json NavigationHandler::Navigate(const nlohmann::json& params) const {
  try {
    TabLease lease;
    const BrowserControlResult resolved = Resolve(runtime_, params, &lease);
    if (!resolved.ok) return ControlError(resolved);
    TabSnapshot tab;
    const BrowserControlResult result = RequireBrowserControl(runtime_).Navigate(lease, RequireString(params, "url"), &tab,
                                                                                  ControlTimeout(params));
    if (result.ok && runtime_.history_store != nullptr) runtime_.history_store->Record(tab.url, tab.title);
    return SnapshotResponse(result, tab);
  } catch (const std::invalid_argument& exception) { return InvalidParams(exception.what()); }
}

nlohmann::json NavigationHandler::Back(const nlohmann::json& params) const {
  try { TabLease lease; auto result = Resolve(runtime_, params, &lease); TabSnapshot tab;
    if (result.ok) result = RequireBrowserControl(runtime_).Back(lease, &tab, ControlTimeout(params));
    return SnapshotResponse(result, tab); } catch (const std::invalid_argument& exception) { return InvalidParams(exception.what()); }
}

nlohmann::json NavigationHandler::Forward(const nlohmann::json& params) const {
  try { TabLease lease; auto result = Resolve(runtime_, params, &lease); TabSnapshot tab;
    if (result.ok) result = RequireBrowserControl(runtime_).Forward(lease, &tab, ControlTimeout(params));
    return SnapshotResponse(result, tab); } catch (const std::invalid_argument& exception) { return InvalidParams(exception.what()); }
}

nlohmann::json NavigationHandler::Reload(const nlohmann::json& params) const {
  try { TabLease lease; auto result = Resolve(runtime_, params, &lease); TabSnapshot tab;
    if (result.ok) result = RequireBrowserControl(runtime_).Reload(lease, &tab, ControlTimeout(params));
    return SnapshotResponse(result, tab); } catch (const std::invalid_argument& exception) { return InvalidParams(exception.what()); }
}

nlohmann::json NavigationHandler::GetCurrentUrl(const nlohmann::json& params) const {
  try { TabLease lease; const auto result = Resolve(runtime_, params, &lease);
    if (!result.ok) return ControlError(result);
    if (!result.tab) return ErrorResponse("WEBVIEW_ERROR", "Resolved tab has no snapshot");
    return SuccessResponse({{"tab", TabJson(*result.tab)}, {"url", result.tab->url}, {"title", result.tab->title}});
  } catch (const std::invalid_argument& exception) { return InvalidParams(exception.what()); }
}

}  // namespace kelpie
