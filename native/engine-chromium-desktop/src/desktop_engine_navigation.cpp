#include "desktop_engine_impl.h"

#include <limits>
#include <memory>
#include <utility>

// Navigation for the desktop engine: the API's own navigate, back, forward,
// reload and stop, and the per-tab NavigationTracker state behind
// wait-for-navigation. The tracker's load events arrive in
// desktop_engine_client.cpp.
namespace kelpie {

BrowserControlResult DesktopEngine::GetNavigationState(TabLease lease, NavigationState* output,
                                                       Timeout timeout) {
  const auto impl = impl_;
  if (output == nullptr) return BrowserControlResult::Failure("INTERNAL", "navigation state is required");
  auto state = std::make_shared<NavigationState>();
  const auto result = impl->RunOnUi([impl, lease, state] {
    auto* tab = impl->FindTab(lease);
    if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist or is stale");
    state->tab = impl->Snapshot(*tab);
    state->navigation = tab->navigation;
    return BrowserControlResult::Success(state->tab);
  }, timeout);
  if (result.ok) *output = std::move(*state);
  return result;
}

BrowserControlResult DesktopEngine::MarkNavigationAction(TabLease lease, Timeout timeout) {
  const auto impl = impl_;
  return impl->RunOnUi([impl, lease] {
    auto* tab = impl->FindTab(lease);
    if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist or is stale");
    tab->navigation.MarkAction();
    return BrowserControlResult::Success(impl->Snapshot(*tab));
  }, timeout);
}

BrowserControlResult DesktopEngine::Navigate(std::optional<TabLease> lease, std::string url,
                                             TabSnapshot* tab, Timeout timeout) {
  const auto impl = impl_;
  auto navigated = std::make_shared<TabSnapshot>();
  const auto result = impl->RunOnUi([impl, lease, url = std::move(url), navigated] {
    if (!IsNavigableUrl(url)) return BrowserControlResult::Failure("INVALID_URL", "url must be an absolute URL");
    DesktopEngine::Impl::Tab* target = nullptr;
    if (lease) target = impl->FindTab(*lease); else if (impl->tabs.size() == 1) target = impl->ActiveTab();
    if (!target) return BrowserControlResult::Failure(lease ? "TAB_NOT_FOUND" : "TAB_REQUIRED", "A current tab lease is required");
    if (target->navigation.started == std::numeric_limits<std::uint64_t>::max()) {
      return BrowserControlResult::Failure("NAVIGATION_EXHAUSTED", "No more navigation requests are available");
    }
    target->navigation.ApiNavigationRequested();
    target->loading = true;
    target->browser->GetMainFrame()->LoadURL(url);
    target->url = url;
    *navigated = impl->Snapshot(*target);
    return BrowserControlResult::Success(*navigated);
  }, timeout);
  if (result.ok && tab) *tab = *navigated;
  return result;
}

BrowserControlResult DesktopEngine::Back(TabLease lease, TabSnapshot* tab, Timeout timeout) {
  const auto impl = impl_;
  auto state = std::make_shared<TabSnapshot>();
  const auto result = impl->RunOnUi([impl, lease, state] { auto* target=impl->FindTab(lease); if(!target) return BrowserControlResult::Failure("TAB_NOT_FOUND","The tab does not exist or is stale"); target->navigation.ApiNavigationRequested(); target->loading=true; target->browser->GoBack(); *state=impl->Snapshot(*target); return BrowserControlResult::Success(*state); }, timeout);
  if (result.ok && tab) *tab=*state; return result;
}
BrowserControlResult DesktopEngine::Forward(TabLease lease, TabSnapshot* tab, Timeout timeout) {
  const auto impl = impl_;
  auto state = std::make_shared<TabSnapshot>();
  const auto result = impl->RunOnUi([impl, lease, state] { auto* target=impl->FindTab(lease); if(!target) return BrowserControlResult::Failure("TAB_NOT_FOUND","The tab does not exist or is stale"); target->navigation.ApiNavigationRequested(); target->loading=true; target->browser->GoForward(); *state=impl->Snapshot(*target); return BrowserControlResult::Success(*state); }, timeout);
  if (result.ok && tab) *tab=*state; return result;
}
BrowserControlResult DesktopEngine::Reload(TabLease lease, TabSnapshot* tab, Timeout timeout) {
  const auto impl = impl_;
  auto state = std::make_shared<TabSnapshot>();
  const auto result = impl->RunOnUi([impl, lease, state] { auto* target=impl->FindTab(lease); if(!target) return BrowserControlResult::Failure("TAB_NOT_FOUND","The tab does not exist or is stale"); target->navigation.ApiNavigationRequested(); target->loading=true; target->browser->Reload(); *state=impl->Snapshot(*target); return BrowserControlResult::Success(*state); }, timeout);
  if (result.ok && tab) *tab=*state; return result;
}
BrowserControlResult DesktopEngine::StopLoading(TabLease lease, TabSnapshot* tab, Timeout timeout) {
  const auto impl = impl_;
  auto state = std::make_shared<TabSnapshot>();
  const auto result = impl->RunOnUi([impl, lease, state] { auto* target=impl->FindTab(lease); if(!target) return BrowserControlResult::Failure("TAB_NOT_FOUND","The tab does not exist or is stale"); target->browser->StopLoad(); *state=impl->Snapshot(*target); return BrowserControlResult::Success(*state); }, timeout);
  if (result.ok && tab) *tab=*state; return result;
}

}  // namespace kelpie
