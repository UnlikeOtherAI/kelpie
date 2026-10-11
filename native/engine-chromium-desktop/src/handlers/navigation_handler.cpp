#include "navigation_handler.h"

#include <chrono>
#include <limits>

#include "navigation_wait.h"

namespace kelpie {
namespace {

BrowserControlResult Resolve(const DesktopHandlerRuntime& runtime, const nlohmann::json& params,
                             TabLease* lease) {
  return ResolveTabForRequest(RequireBrowserControl(runtime), params, lease, ControlTimeout(params));
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
    // `timeout` bounds the whole call, including the wait for the page to load
    // (docs/api/core.md), so the next command sees the new document.
    const auto started = std::chrono::steady_clock::now();
    const auto deadline = started + ControlTimeout(params);
    BrowserNavigationState before;
    const bool pinned_document = lease.document_version.has_value();
    if (pinned_document) {
      const BrowserControlResult observed = RequireBrowserControl(runtime_).GetNavigationState(lease, &before, ControlTimeout(params));
      if (!observed.ok) return ControlError(observed);
      if (before.requested == std::numeric_limits<std::uint64_t>::max())
        return ErrorResponse("NAVIGATION_EXHAUSTED", "No more navigation requests are available");
    }
    const std::string destination = RequireString(params, "url");
    TabSnapshot tab;
    const BrowserControlResult result = RequireBrowserControl(runtime_).Navigate(lease, destination, &tab,
                                                                                  ControlTimeout(params));
    if (!result.ok) return ControlError(result);
    if (pinned_document) {
      const NavigationWaitResult waited = AwaitOwnedNavigation(runtime_, lease, before.requested + 1,
                                                               before.tab.document_version, destination, deadline);
      if (!waited.ok) return waited.error;
      if (runtime_.history_store != nullptr) runtime_.history_store->Record(waited.tab.url, waited.tab.title);
      const auto load_ms = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - started);
      nlohmann::json response = SnapshotResponse(result, waited.tab);
      response["loadTime"] = load_ms.count();
      return response;
    }
    BrowserNavigationState requested;
    const BrowserControlResult state = RequireBrowserControl(runtime_).GetNavigationState(lease, &requested, ControlTimeout(params));
    if (!state.ok) return ControlError(state);
    const NavigationWaitResult waited = AwaitNavigation(runtime_, lease, requested.requested, deadline);
    if (!waited.ok) return waited.error;
    if (runtime_.history_store != nullptr) runtime_.history_store->Record(waited.tab.url, waited.tab.title);
    const auto load_ms = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - started);
    nlohmann::json response = SnapshotResponse(result, waited.tab);
    response["loadTime"] = load_ms.count();
    return response;
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
