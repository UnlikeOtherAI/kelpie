#include "desktop_engine_control_support.h"

#include <condition_variable>
#include <ctime>
#include <functional>
#include <thread>
#include <iomanip>
#include <limits>
#include <memory>
#include <utility>

#include "include/base/cef_bind.h"
#include "include/base/cef_callback.h"
#include "include/cef_task.h"
#include "include/cef_parser.h"
#include "include/wrapper/cef_closure_task.h"
#include "include/cef_urlrequest.h"
#include "include/cef_request_context.h"
#include "kelpie/internal_scheme.h"
#include "kelpie/partition.h"
#if defined(_WIN32)
#include <windows.h>
#endif

namespace kelpie {
namespace {

BrowserControlResult TimeoutResult() {
  BrowserControlResult result = BrowserControlResult::Failure("TIMEOUT", "Browser operation timed out");
  result.operation_may_have_completed = true;
  return result;
}

struct UiOperation {
  enum class State { kPending, kRunning, kCompleted, kAbandoned };
  std::mutex mutex;
  std::condition_variable ready;
  std::atomic<State> state = State::kPending;
  std::function<BrowserControlResult()> call;
  BrowserControlResult result;
};

void RunUiOperation(std::shared_ptr<UiOperation> operation) {
  UiOperation::State expected = UiOperation::State::kPending;
  if (!operation->state.compare_exchange_strong(expected, UiOperation::State::kRunning)) return;
  BrowserControlResult result = operation->call();
  {
    std::lock_guard<std::mutex> lock(operation->mutex);
    expected = UiOperation::State::kRunning;
    if (!operation->state.compare_exchange_strong(expected, UiOperation::State::kCompleted)) return;
    operation->result = std::move(result);
  }
  operation->ready.notify_all();
}

bool IsNavigableUrl(const std::string& url) {
  if (url.empty()) return false;
  CefURLParts parts;
  // `kelpie://` is checked explicitly: CefParseURL only recognises a custom
  // scheme once Chromium has been initialised in this process, and the shell
  // creates the start page tab through the same validator.
  return CefParseURL(url, parts) || IsInternalSchemeUrl(url) ||
         url.rfind("about:", 0) == 0 || url.rfind("data:", 0) == 0;
}

}  // namespace

using namespace engine_control;

DesktopEngine::Impl::Tab* DesktopEngine::Impl::FindTab(const TabLease& lease) {
  for (auto& tab : tabs) {
    if (tab.id == lease.id) {
      return !tab.closing && tab.generation == lease.generation ? &tab : nullptr;
    }
  }
  return nullptr;
}

DesktopEngine::Impl::Tab* DesktopEngine::Impl::FindTab(CefRefPtr<CefBrowser> candidate) {
  for (auto& tab : tabs) {
    if (!tab.closing && tab.browser && tab.browser->IsSame(candidate)) return &tab;
  }
  return nullptr;
}

DesktopEngine::Impl::Tab* DesktopEngine::Impl::ActiveTab() {
  return browser ? FindTab(browser) : nullptr;
}

TabSnapshot DesktopEngine::Impl::Snapshot(const Tab& tab) const {
  TabSnapshot snapshot{tab.id, tab.generation, tab.url, tab.title,
                       browser && browser->IsSame(tab.browser), tab.loading,
                       tab.can_go_back, tab.can_go_forward,
                       IsStartPageUrl(tab.url),
                       // Shared, not copied: see the field comment on TabSnapshot.
                       tab.favicon_png_base64};
  snapshot.name = tab.name;
  snapshot.partition = tab.partition;
  // `persistent` describes the partition, so a tab in the default shared store
  // reports neither field rather than a misleading default.
  if (tab.partition) {
    const auto* entry = partitions.Find(*tab.partition);
    snapshot.persistent = entry == nullptr ? true : entry->persistent;
  }
  return snapshot;
}

void DesktopEngine::Impl::UpdateActiveState() {
  if (auto* active = ActiveTab()) {
    if (viewport.offscreen) {
      bool changed;
      { std::lock_guard<std::mutex> lock(mutex);
        changed = frame.tab_id != active->id || frame.generation != active->generation;
        if (changed) { frame = {active->id, active->generation, 0, 0, {}}; popup = {}; }
      }
      if (changed) { active->browser->GetHost()->WasResized(); active->browser->GetHost()->Invalidate(PET_VIEW); }
    }
    current_url = active->url;
    current_title = active->title;
    loading = active->loading;
    can_go_back = active->can_go_back;
    can_go_forward = active->can_go_forward;
  }
}

BrowserControlResult DesktopEngine::Impl::RunOnUi(std::function<BrowserControlResult()> operation,
                                                   Timeout timeout) {
  if (!initialized || shutting_down) return BrowserControlResult::Failure("INTERNAL", "Browser runtime is not running");
  if (CefCurrentlyOn(TID_UI)) return operation();
  auto pending = std::make_shared<UiOperation>();
  pending->call = [this, operation = std::move(operation)]() mutable {
    // A task admitted before Shutdown must not touch CEF after shutdown starts.
    // Recheck on the UI thread immediately before invoking the browser operation.
    if (!initialized || shutting_down.load()) {
      return BrowserControlResult::Failure("INTERNAL", "Browser runtime is shutting down");
    }
    return operation();
  };
  if (!CefPostTask(TID_UI, CefCreateClosureTask(base::BindOnce(&RunUiOperation, pending)))) {
    return BrowserControlResult::Failure("INTERNAL", "Unable to schedule browser operation");
  }
  std::unique_lock<std::mutex> lock(pending->mutex);
  if (pending->ready.wait_for(lock, timeout, [&] {
        return pending->state.load() == UiOperation::State::kCompleted;
      })) return pending->result;
  UiOperation::State state = pending->state.load();
  if (state == UiOperation::State::kCompleted) return pending->result;
  if (state == UiOperation::State::kPending) {
    UiOperation::State expected = UiOperation::State::kPending;
    pending->state.compare_exchange_strong(expected, UiOperation::State::kAbandoned);
  } else if (state == UiOperation::State::kRunning) {
    pending->state.store(UiOperation::State::kAbandoned);
  }
  return TimeoutResult();
}

BrowserControlResult DesktopEngine::Impl::CreateTabOnUi(const NewTabRequest& request,
                                                        TabSnapshot* snapshot,
                                                        std::optional<std::string> restored_id) {
  // A tab with no URL opens Kelpie's start page, the same as macOS. This is the
  // one place that decides it, so the `+` button, `new-tab` over HTTP/MCP, and
  // the replacement tab after the last close all agree.
  const std::string url = request.url.empty() ? std::string(kStartPageUrl) : request.url;
  if (!IsNavigableUrl(url)) return BrowserControlResult::Failure("INVALID_URL", "url must be an absolute URL");
  if (!restored_id && next_tab_id == std::numeric_limits<std::uint64_t>::max()) {
    return BrowserControlResult::Failure("TAB_ID_EXHAUSTED", "No more tab identifiers are available");
  }
  // nullptr is CEF's global request context: the default shared store every
  // ordinary tab uses. Only a named partition swaps in a private one.
  CefRefPtr<CefRequestContext> request_context;
  DesktopPartitionRegistry::Entry* partition = nullptr;
  if (request.partition) {
    const PartitionValidation validation = ValidatePartition(*request.partition);
    if (!validation.ok) {
      return BrowserControlResult::Failure(
          "INVALID_PARTITION",
          "Invalid partition \"" + *request.partition + "\": " +
              PartitionErrorMessage(validation.reason));
    }
    auto* existing = partitions.Find(*request.partition);
    if (existing != nullptr && existing->deleting) {
      return BrowserControlResult::Failure(
          "PARTITION_DELETING", "Partition \"" + *request.partition +
                                    "\" is being deleted. Retry once delete-partition returns.");
    }
    partition = partitions.Acquire(*request.partition, request.persistent);
    if (partition == nullptr) {
      return BrowserControlResult::Failure("WEBVIEW_ERROR",
                                           "Chromium could not create the storage partition");
    }
    if (!partition->ready()) {
      // Internal sentinel. DesktopEngine::CreateTab retries off the UI thread
      // until the store has loaded; nothing else can wait here, because the
      // callback that flips this flag arrives on this very thread.
      return BrowserControlResult::Failure(kPartitionNotReady,
                                           "The storage partition is still loading");
    }
    request_context = partition->context;
  }
  CefWindowInfo window_info;
  const std::string id = restored_id ? *restored_id : "tab-" + std::to_string(next_tab_id);
  if (config.mode == DesktopEngine::Mode::kOffscreen) {
    window_info.SetAsWindowless(0);
  } else if (config.configure_tab_window_info) {
    config.configure_tab_window_info(static_cast<void*>(&window_info), id);
  } else if (config.configure_window_info) {
    config.configure_window_info(static_cast<void*>(&window_info));
  } else {
    return BrowserControlResult::Failure("INTERNAL", "No native browser window factory is configured");
  }
  CefBrowserSettings settings;
  CefRefPtr<CefBrowser> created =
      CefBrowserHost::CreateBrowserSync(window_info, client, url, settings, nullptr, request_context);
  if (!created) return BrowserControlResult::Failure("INTERNAL", "CEF did not create the tab");
  if (!restored_id) ++next_tab_id;
  Tab tab;
  tab.id = id;
  tab.browser = created;
  tab.devtools = NewDevToolsSession(created);
  tab.url = url;
  tab.name = request.name;
  if (partition != nullptr) tab.partition = partition->id;
  tabs.push_back(std::move(tab));
#if defined(_WIN32)
  if (const auto window = created->GetHost()->GetWindowHandle()) ShowWindow(window, SW_HIDE);
#endif
  RecountPartitions();
  Tab& created_tab = tabs.back();
  const TabSnapshot state = Snapshot(created_tab);
  if (snapshot) *snapshot = state;
  return BrowserControlResult::Success(state);
}

BrowserControlResult DesktopEngine::GetTabs(std::vector<TabSnapshot>* output, Timeout timeout) {
  const auto impl = impl_;
  if (!output) return BrowserControlResult::Failure("INTERNAL", "tabs is required");
  auto collected = std::make_shared<std::vector<TabSnapshot>>();
  const auto result = impl->RunOnUi([impl, collected] {
    collected->clear();
    for (const auto& tab : impl->tabs) {
      if (!tab.closing) collected->push_back(impl->Snapshot(tab));
    }
    return BrowserControlResult::Success(impl->ActiveTab() ? std::optional(impl->Snapshot(*impl->ActiveTab())) : std::nullopt);
  }, timeout);
  if (result.ok) *output = *collected;
  return result;
}

BrowserControlResult DesktopEngine::GetSessionState(SessionState* output, Timeout timeout) {
  const auto impl = impl_;
  if (output == nullptr) return BrowserControlResult::Failure("INTERNAL", "session state is required");
  auto collected = std::make_shared<SessionState>();
  const auto result = impl->RunOnUi([impl, collected] {
    collected->next_tab_id = impl->next_tab_id;
    collected->tabs.clear();
    for (const auto& tab : impl->tabs) {
      if (tab.closing) continue;
      DesktopEngine::RestoredTab entry{tab.id, tab.url,
                                       impl->browser && impl->browser->IsSame(tab.browser)};
      entry.name = tab.name;
      entry.partition = tab.partition;
      if (tab.partition) {
        const auto* found = impl->partitions.Find(*tab.partition);
        entry.persistent = found == nullptr ? true : found->persistent;
      }
      collected->tabs.push_back(std::move(entry));
    }
    return BrowserControlResult::Success(
        impl->ActiveTab() ? std::optional(impl->Snapshot(*impl->ActiveTab())) : std::nullopt);
  }, timeout);
  if (result.ok) *output = std::move(*collected);
  return result;
}

BrowserControlResult DesktopEngine::GetNavigationState(TabLease lease, NavigationState* output,
                                                       Timeout timeout) {
  const auto impl = impl_;
  if (output == nullptr) return BrowserControlResult::Failure("INTERNAL", "navigation state is required");
  auto state = std::make_shared<NavigationState>();
  const auto result = impl->RunOnUi([impl, lease, state] {
    auto* tab = impl->FindTab(lease);
    if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist or is stale");
    state->tab = impl->Snapshot(*tab);
    state->requested = tab->navigation_requested;
    state->completed = tab->navigation_completed;
    state->error = tab->navigation_error;
    return BrowserControlResult::Success(state->tab);
  }, timeout);
  if (result.ok) *output = std::move(*state);
  return result;
}

BrowserControlResult DesktopEngine::ResolveTab(const std::optional<std::string>& id,
                                               const std::optional<std::uint64_t>& generation,
                                               TabLease* lease, Timeout timeout) {
  const auto impl = impl_;
  if (!lease) return BrowserControlResult::Failure("INTERNAL", "lease is required");
  const auto tab_id = id;
  const auto requested_generation = generation;
  auto resolved = std::make_shared<TabLease>();
  const auto result = impl->RunOnUi([impl, tab_id, requested_generation, resolved] {
    DesktopEngine::Impl::Tab* tab = nullptr;
    if (tab_id) {
      for (auto& candidate : impl->tabs) {
        if (!candidate.closing && candidate.id == *tab_id) { tab = &candidate; break; }
      }
      if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist");
      if (requested_generation && tab->generation != *requested_generation) {
        return BrowserControlResult::Failure("TAB_STALE", "The tab lease is stale");
      }
    } else {
      if (impl->tabs.size() != 1) return BrowserControlResult::Failure("TAB_REQUIRED", "tabId is required when more than one tab is open");
      tab = impl->ActiveTab();
    }
    if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "No active tab exists");
    *resolved = {tab->id, tab->generation};
    return BrowserControlResult::Success(impl->Snapshot(*tab));
  }, timeout);
  if (result.ok) *lease = *resolved;
  return result;
}

bool DesktopEngine::IsActiveNativeBrowserAttached(void* parent_window, Timeout timeout) {
  const auto impl = impl_;
  return impl->RunOnUi([impl, parent_window] {
#if defined(_WIN32)
    auto* active = impl->ActiveTab();
    if (active == nullptr || !active->browser || !active->browser->GetHost()) {
      return BrowserControlResult::Failure("TAB_NOT_FOUND", "No active browser tab exists");
    }
    const HWND window = active->browser->GetHost()->GetWindowHandle();
    RECT bounds{};
    // The child's own WS_VISIBLE, not IsWindowVisible: the latter also demands
    // every ancestor be visible, so a shell launched hidden (SW_HIDE) would
    // fail startup although its browser child is attached and rendering.
    const bool child_shown = (GetWindowLongPtrW(window, GWL_STYLE) & WS_VISIBLE) != 0;
    if (window == nullptr || GetParent(window) != static_cast<HWND>(parent_window) ||
        !child_shown || !GetWindowRect(window, &bounds) ||
        bounds.right <= bounds.left || bounds.bottom <= bounds.top) {
      return BrowserControlResult::Failure("BROWSER_NOT_ATTACHED", "The active browser child is not attached");
    }
    return BrowserControlResult::Success();
#else
    (void)parent_window;
    return BrowserControlResult::Failure("UNSUPPORTED", "Native child validation is only available on Windows");
#endif
  }, timeout).ok;
}

BrowserControlResult DesktopEngine::CreateTab(const NewTabRequest& request, TabSnapshot* tab,
                                              Timeout timeout) {
  const auto impl = impl_;
  auto created = std::make_shared<TabSnapshot>();
  const auto started = std::chrono::steady_clock::now();
  BrowserControlResult result;
  // The first tab in a new persistent partition has to wait for Chromium to
  // load that store. Waiting here, on the calling thread, keeps the UI thread
  // free to do the loading.
  while (true) {
    const auto remaining = RemainingTimeout(started, timeout);
    if (remaining <= Timeout::zero()) break;
    result = impl->RunOnUi([impl, request, created] {
      return impl->CreateTabOnUi(request, created.get());
    }, remaining);
    if (result.ok || result.error_code != kPartitionNotReady) {
      if (result.ok && tab) *tab = *created;
      return result;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
  }
  return BrowserControlResult::Failure(
      "WEBVIEW_ERROR", "The storage partition did not finish loading in time");
}

BrowserControlResult DesktopEngine::ActivateTab(TabLease lease, Timeout timeout) {
  const auto impl = impl_;
  return impl->RunOnUi([impl, lease] {
    auto* tab = impl->FindTab(lease);
    if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist or is stale");
#if defined(_WIN32)
    if (impl->browser && impl->browser->GetHost()) ShowWindow(impl->browser->GetHost()->GetWindowHandle(), SW_HIDE);
    if (tab->browser && tab->browser->GetHost()) ShowWindow(tab->browser->GetHost()->GetWindowHandle(), SW_SHOW);
#endif
    if (impl->viewport.offscreen && impl->browser) impl->browser->GetHost()->SetFocus(false);
    impl->browser = tab->browser;
    impl->UpdateActiveState();
    return BrowserControlResult::Success(impl->Snapshot(*tab));
  }, timeout);
}

BrowserControlResult DesktopEngine::CloseTab(TabLease lease, Timeout timeout) {
  const auto impl = impl_;
  return impl->RunOnUi([impl, lease] {
    auto* tab = impl->FindTab(lease);
    if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist or is stale");
    const auto closing_index = static_cast<std::size_t>(tab - impl->tabs.data());
    CefRefPtr<CefBrowser> closing = tab->browser;
    CefRefPtr<DesktopDevToolsSession> closing_devtools = tab->devtools;
    const bool was_active = impl->browser && impl->browser->IsSame(closing);
    std::size_t live_tabs = 0;
    for (const auto& candidate : impl->tabs) if (!candidate.closing) ++live_tabs;
    if (live_tabs == 1) {
      TabSnapshot replacement;
      // Closing the last tab leaves the start page behind, matching macOS.
      const auto created = impl->CreateTabOnUi(std::string(), &replacement);
      if (!created.ok) return created;
      impl->browser = impl->tabs.back().browser;
    } else if (was_active) {
      for (const auto& candidate : impl->tabs) {
        if (!candidate.closing && !candidate.browser->IsSame(closing)) {
          impl->browser = candidate.browser;
          break;
        }
      }
    }
    if (closing_devtools) closing_devtools->CancelAll();
#if defined(_WIN32)
    if (was_active && impl->browser && impl->browser->GetHost()) {
      ShowWindow(impl->browser->GetHost()->GetWindowHandle(), SW_SHOW);
    }
#endif
    // Explicit agent/UI tab closes are force-closes. This avoids a hidden,
    // permanently closing tab when a beforeunload prompt rejects CloseBrowser(false).
    // The CEF lifetime callback remains the sole owner-removal point.
    impl->tabs[closing_index].closing = true;
    closing->GetHost()->CloseBrowser(true);
    impl->RecountPartitions();
    impl->UpdateActiveState();
    return BrowserControlResult::Success(impl->ActiveTab() ? std::optional(impl->Snapshot(*impl->ActiveTab())) : std::nullopt);
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
    if (target->navigation_requested == std::numeric_limits<std::uint64_t>::max()) {
      return BrowserControlResult::Failure("NAVIGATION_EXHAUSTED", "No more navigation requests are available");
    }
    ++target->navigation_requested;
    target->navigation_error.clear();
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
  const auto result = impl->RunOnUi([impl, lease, state] { auto* target=impl->FindTab(lease); if(!target) return BrowserControlResult::Failure("TAB_NOT_FOUND","The tab does not exist or is stale"); ++target->navigation_requested; target->navigation_error.clear(); target->loading=true; target->browser->GoBack(); *state=impl->Snapshot(*target); return BrowserControlResult::Success(*state); }, timeout);
  if (result.ok && tab) *tab=*state; return result;
}
BrowserControlResult DesktopEngine::Forward(TabLease lease, TabSnapshot* tab, Timeout timeout) {
  const auto impl = impl_;
  auto state = std::make_shared<TabSnapshot>();
  const auto result = impl->RunOnUi([impl, lease, state] { auto* target=impl->FindTab(lease); if(!target) return BrowserControlResult::Failure("TAB_NOT_FOUND","The tab does not exist or is stale"); ++target->navigation_requested; target->navigation_error.clear(); target->loading=true; target->browser->GoForward(); *state=impl->Snapshot(*target); return BrowserControlResult::Success(*state); }, timeout);
  if (result.ok && tab) *tab=*state; return result;
}
BrowserControlResult DesktopEngine::Reload(TabLease lease, TabSnapshot* tab, Timeout timeout) {
  const auto impl = impl_;
  auto state = std::make_shared<TabSnapshot>();
  const auto result = impl->RunOnUi([impl, lease, state] { auto* target=impl->FindTab(lease); if(!target) return BrowserControlResult::Failure("TAB_NOT_FOUND","The tab does not exist or is stale"); ++target->navigation_requested; target->navigation_error.clear(); target->loading=true; target->browser->Reload(); *state=impl->Snapshot(*target); return BrowserControlResult::Success(*state); }, timeout);
  if (result.ok && tab) *tab=*state; return result;
}
BrowserControlResult DesktopEngine::StopLoading(TabLease lease, TabSnapshot* tab, Timeout timeout) {
  const auto impl = impl_;
  auto state = std::make_shared<TabSnapshot>();
  const auto result = impl->RunOnUi([impl, lease, state] { auto* target=impl->FindTab(lease); if(!target) return BrowserControlResult::Failure("TAB_NOT_FOUND","The tab does not exist or is stale"); target->browser->StopLoad(); *state=impl->Snapshot(*target); return BrowserControlResult::Success(*state); }, timeout);
  if (result.ok && tab) *tab=*state; return result;
}

}  // namespace kelpie
