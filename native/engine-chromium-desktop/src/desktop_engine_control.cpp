#include "desktop_engine_impl.h"

#include <condition_variable>
#include <memory>
#include <sstream>
#include <utility>

#include "include/base/cef_bind.h"
#include "include/base/cef_callback.h"
#include "include/cef_task.h"
#include "include/cef_parser.h"
#include "include/wrapper/cef_closure_task.h"
#include "include/cef_urlrequest.h"
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
  expected = UiOperation::State::kRunning;
  if (!operation->state.compare_exchange_strong(expected, UiOperation::State::kCompleted)) {
    return;
  }
  {
    std::lock_guard<std::mutex> lock(operation->mutex);
    operation->result = std::move(result);
  }
  operation->ready.notify_all();
}

bool IsNavigableUrl(const std::string& url) {
  if (url.empty()) return false;
  CefURLParts parts;
  return CefParseURL(url, parts) || url.rfind("about:", 0) == 0 || url.rfind("data:", 0) == 0;
}

struct PendingDevTools {
  CefRefPtr<DesktopDevToolsSession> session;
  std::shared_ptr<DesktopDevToolsSession::Operation> operation;
};

BrowserControlResult DevToolsResult(const DesktopDevToolsSession::Result& result) {
  BrowserControlResult output = result.ok ? BrowserControlResult::Success()
                                         : BrowserControlResult::Failure(result.error_code, result.message);
  output.operation_may_have_completed = result.operation_may_have_completed;
  return output;
}

}  // namespace

DesktopEngine::Impl::Tab* DesktopEngine::Impl::FindTab(const TabLease& lease) {
  for (auto& tab : tabs) {
    if (tab.id == lease.id) {
      return tab.generation == lease.generation ? &tab : nullptr;
    }
  }
  return nullptr;
}

DesktopEngine::Impl::Tab* DesktopEngine::Impl::FindTab(CefRefPtr<CefBrowser> candidate) {
  for (auto& tab : tabs) {
    if (tab.browser && tab.browser->IsSame(candidate)) return &tab;
  }
  return nullptr;
}

DesktopEngine::Impl::Tab* DesktopEngine::Impl::ActiveTab() {
  return browser ? FindTab(browser) : nullptr;
}

TabSnapshot DesktopEngine::Impl::Snapshot(const Tab& tab) const {
  return {tab.id, tab.generation, tab.url, tab.title,
          browser && browser->IsSame(tab.browser), tab.loading,
          tab.can_go_back, tab.can_go_forward};
}

void DesktopEngine::Impl::UpdateActiveState() {
  if (auto* active = ActiveTab()) {
    current_url = active->url;
    current_title = active->title;
    loading = active->loading;
    can_go_back = active->can_go_back;
    can_go_forward = active->can_go_forward;
  }
}

BrowserControlResult DesktopEngine::Impl::RunOnUi(std::function<BrowserControlResult()> operation,
                                                   Timeout timeout) {
  if (!initialized) return BrowserControlResult::Failure("INTERNAL", "Browser runtime is not running");
  if (CefCurrentlyOn(TID_UI)) return operation();
  auto pending = std::make_shared<UiOperation>();
  pending->call = std::move(operation);
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

BrowserControlResult DesktopEngine::Impl::CreateTabOnUi(const std::string& url, TabSnapshot* snapshot) {
  if (!IsNavigableUrl(url)) return BrowserControlResult::Failure("INVALID_URL", "url must be an absolute URL");
  CefWindowInfo window_info;
  const std::string id = "tab-" + std::to_string(++next_tab_id);
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
  CefRefPtr<CefBrowser> created = CefBrowserHost::CreateBrowserSync(window_info, client, url, settings, nullptr, nullptr);
  if (!created) return BrowserControlResult::Failure("INTERNAL", "CEF did not create the tab");
  Tab tab;
  tab.id = id;
  tab.browser = created;
  tab.devtools = new DesktopDevToolsSession();
  tab.url = url;
  tabs.push_back(std::move(tab));
#if defined(_WIN32)
  if (const auto window = created->GetHost()->GetWindowHandle()) ShowWindow(window, SW_HIDE);
#endif
  Tab& created_tab = tabs.back();
  const TabSnapshot state = Snapshot(created_tab);
  if (snapshot) *snapshot = state;
  return BrowserControlResult::Success(state);
}

BrowserControlResult DesktopEngine::GetTabs(std::vector<TabSnapshot>* output, Timeout timeout) {
  if (!output) return BrowserControlResult::Failure("INTERNAL", "tabs is required");
  auto collected = std::make_shared<std::vector<TabSnapshot>>();
  const auto result = impl_->RunOnUi([this, collected] {
    collected->clear();
    for (const auto& tab : impl_->tabs) collected->push_back(impl_->Snapshot(tab));
    return BrowserControlResult::Success(impl_->ActiveTab() ? std::optional(impl_->Snapshot(*impl_->ActiveTab())) : std::nullopt);
  }, timeout);
  if (result.ok) *output = *collected;
  return result;
}

BrowserControlResult DesktopEngine::ResolveTab(const std::optional<std::string>& id,
                                               const std::optional<std::uint64_t>& generation,
                                               TabLease* lease, Timeout timeout) {
  if (!lease) return BrowserControlResult::Failure("INTERNAL", "lease is required");
  const auto tab_id = id;
  const auto requested_generation = generation;
  auto resolved = std::make_shared<TabLease>();
  const auto result = impl_->RunOnUi([this, tab_id, requested_generation, resolved] {
    DesktopEngine::Impl::Tab* tab = nullptr;
    if (tab_id) {
      for (auto& candidate : impl_->tabs) if (candidate.id == *tab_id) { tab = &candidate; break; }
      if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist");
      if (requested_generation && tab->generation != *requested_generation) {
        return BrowserControlResult::Failure("TAB_STALE", "The tab lease is stale");
      }
    } else {
      if (impl_->tabs.size() != 1) return BrowserControlResult::Failure("TAB_REQUIRED", "tabId is required when more than one tab is open");
      tab = impl_->ActiveTab();
    }
    if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "No active tab exists");
    *resolved = {tab->id, tab->generation};
    return BrowserControlResult::Success(impl_->Snapshot(*tab));
  }, timeout);
  if (result.ok) *lease = *resolved;
  return result;
}

BrowserControlResult DesktopEngine::CreateTab(std::string url, TabSnapshot* tab, Timeout timeout) {
  auto created = std::make_shared<TabSnapshot>();
  const auto result = impl_->RunOnUi([this, url = std::move(url), created] {
    return impl_->CreateTabOnUi(url, created.get());
  }, timeout);
  if (result.ok && tab) *tab = *created;
  return result;
}

BrowserControlResult DesktopEngine::ActivateTab(TabLease lease, Timeout timeout) {
  return impl_->RunOnUi([this, lease] {
    auto* tab = impl_->FindTab(lease);
    if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist or is stale");
#if defined(_WIN32)
    if (impl_->browser && impl_->browser->GetHost()) ShowWindow(impl_->browser->GetHost()->GetWindowHandle(), SW_HIDE);
    if (tab->browser && tab->browser->GetHost()) ShowWindow(tab->browser->GetHost()->GetWindowHandle(), SW_SHOW);
#endif
    impl_->browser = tab->browser;
    impl_->UpdateActiveState();
    return BrowserControlResult::Success(impl_->Snapshot(*tab));
  }, timeout);
}

BrowserControlResult DesktopEngine::CloseTab(TabLease lease, Timeout timeout) {
  return impl_->RunOnUi([this, lease] {
    auto* tab = impl_->FindTab(lease);
    if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist or is stale");
    CefRefPtr<CefBrowser> closing = tab->browser;
    CefRefPtr<DesktopDevToolsSession> closing_devtools = tab->devtools;
    const bool was_active = impl_->browser && impl_->browser->IsSame(closing);
    if (impl_->tabs.size() == 1) {
      TabSnapshot replacement;
      const auto created = impl_->CreateTabOnUi("about:blank", &replacement);
      if (!created.ok) return created;
      impl_->browser = impl_->tabs.back().browser;
    } else if (was_active) {
      for (const auto& candidate : impl_->tabs) {
        if (!candidate.browser->IsSame(closing)) { impl_->browser = candidate.browser; break; }
      }
    }
    if (closing_devtools) closing_devtools->CancelAll();
#if defined(_WIN32)
    if (was_active && impl_->browser && impl_->browser->GetHost()) {
      ShowWindow(impl_->browser->GetHost()->GetWindowHandle(), SW_SHOW);
    }
#endif
    impl_->tabs.erase(std::remove_if(impl_->tabs.begin(), impl_->tabs.end(),
        [&closing](const DesktopEngine::Impl::Tab& candidate) { return candidate.browser->IsSame(closing); }),
        impl_->tabs.end());
    closing->GetHost()->CloseBrowser(false);
    impl_->UpdateActiveState();
    return BrowserControlResult::Success(impl_->ActiveTab() ? std::optional(impl_->Snapshot(*impl_->ActiveTab())) : std::nullopt);
  }, timeout);
}

BrowserControlResult DesktopEngine::Navigate(std::optional<TabLease> lease, std::string url,
                                             TabSnapshot* tab, Timeout timeout) {
  auto navigated = std::make_shared<TabSnapshot>();
  const auto result = impl_->RunOnUi([this, lease, url = std::move(url), navigated] {
    if (!IsNavigableUrl(url)) return BrowserControlResult::Failure("INVALID_URL", "url must be an absolute URL");
    DesktopEngine::Impl::Tab* target = nullptr;
    if (lease) target = impl_->FindTab(*lease); else if (impl_->tabs.size() == 1) target = impl_->ActiveTab();
    if (!target) return BrowserControlResult::Failure(lease ? "TAB_NOT_FOUND" : "TAB_REQUIRED", "A current tab lease is required");
    target->browser->GetMainFrame()->LoadURL(url);
    target->url = url;
    *navigated = impl_->Snapshot(*target);
    return BrowserControlResult::Success(*navigated);
  }, timeout);
  if (result.ok && tab) *tab = *navigated;
  return result;
}

BrowserControlResult DesktopEngine::Back(TabLease lease, TabSnapshot* tab, Timeout timeout) {
  auto state = std::make_shared<TabSnapshot>();
  const auto result = impl_->RunOnUi([this, lease, state] { auto* target=impl_->FindTab(lease); if(!target) return BrowserControlResult::Failure("TAB_NOT_FOUND","The tab does not exist or is stale"); target->browser->GoBack(); *state=impl_->Snapshot(*target); return BrowserControlResult::Success(*state); }, timeout);
  if (result.ok && tab) *tab=*state; return result;
}
BrowserControlResult DesktopEngine::Forward(TabLease lease, TabSnapshot* tab, Timeout timeout) {
  auto state = std::make_shared<TabSnapshot>();
  const auto result = impl_->RunOnUi([this, lease, state] { auto* target=impl_->FindTab(lease); if(!target) return BrowserControlResult::Failure("TAB_NOT_FOUND","The tab does not exist or is stale"); target->browser->GoForward(); *state=impl_->Snapshot(*target); return BrowserControlResult::Success(*state); }, timeout);
  if (result.ok && tab) *tab=*state; return result;
}
BrowserControlResult DesktopEngine::Reload(TabLease lease, TabSnapshot* tab, Timeout timeout) {
  auto state = std::make_shared<TabSnapshot>();
  const auto result = impl_->RunOnUi([this, lease, state] { auto* target=impl_->FindTab(lease); if(!target) return BrowserControlResult::Failure("TAB_NOT_FOUND","The tab does not exist or is stale"); target->browser->Reload(); *state=impl_->Snapshot(*target); return BrowserControlResult::Success(*state); }, timeout);
  if (result.ok && tab) *tab=*state; return result;
}

BrowserControlResult DesktopEngine::Evaluate(TabLease lease, std::string script, Json* value, Timeout timeout) {
  if (value == nullptr) return BrowserControlResult::Failure("INTERNAL", "result is required");
  auto pending = std::make_shared<PendingDevTools>();
  const auto started = impl_->RunOnUi([this, lease, script = std::move(script), pending] {
    auto* tab = impl_->FindTab(lease);
    if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist or is stale");
    pending->session = tab->devtools;
    pending->operation = pending->session->Begin(tab->browser, "Runtime.evaluate",
                                                  DesktopDevToolsSession::EvaluateParams(script));
    return BrowserControlResult::Success(impl_->Snapshot(*tab));
  }, timeout);
  if (!started.ok) return started;
  const auto parsed = DesktopDevToolsSession::ParseEvaluateResult(pending->session->Wait(pending->operation, timeout));
  const auto result = DevToolsResult(parsed);
  if (result.ok) *value = parsed.value;
  return result;
}

BrowserControlResult DesktopEngine::Screenshot(TabLease lease, BrowserScreenshot* image, Timeout timeout) {
  if (image == nullptr) return BrowserControlResult::Failure("INTERNAL", "image is required");
  const auto screenshot_params = DesktopDevToolsSession::ScreenshotParams(Json::object());
  if (!screenshot_params) return BrowserControlResult::Failure("INTERNAL", "Screenshot parameters are invalid");
  auto pending = std::make_shared<PendingDevTools>();
  const auto started = impl_->RunOnUi([this, lease, pending, screenshot_params] {
    auto* tab = impl_->FindTab(lease);
    if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist or is stale");
    pending->session = tab->devtools;
    pending->operation = pending->session->Begin(tab->browser, "Page.captureScreenshot",
                                                  *screenshot_params);
    return BrowserControlResult::Success(impl_->Snapshot(*tab));
  }, timeout);
  if (!started.ok) return started;
  const auto parsed = DesktopDevToolsSession::ParseScreenshotResult(pending->session->Wait(pending->operation, timeout));
  const auto result = DevToolsResult(parsed);
  if (result.ok) {
    image->mime_type = parsed.value.value("mimeType", "image/png");
    image->base64_data = parsed.value.value("data", "");
  }
  return result;
}
BrowserControlResult DesktopEngine::GetCookies(TabLease lease, const Json&, Json*, Timeout timeout) { return Screenshot(lease, nullptr, timeout); }
BrowserControlResult DesktopEngine::SetCookies(TabLease lease, const Json&, Json*, Timeout timeout) { return Screenshot(lease, nullptr, timeout); }
BrowserControlResult DesktopEngine::DeleteCookies(TabLease lease, const Json&, Json*, Timeout timeout) { return Screenshot(lease, nullptr, timeout); }
BrowserControlResult DesktopEngine::DispatchTrustedInput(TabLease lease, const Json& input, Json* output, Timeout timeout) {
  if (input.value("type", "") != "key") return BrowserControlResult::Failure("UNSUPPORTED", "Only native key input is available");
  Json first;
  const auto down = DevTools(lease, "Input.dispatchKeyEvent", DesktopDevToolsSession::TrustedKeyParams(input, false), &first, timeout);
  if (!down.ok) return down;
  Json second;
  const auto up = DevTools(lease, "Input.dispatchKeyEvent", DesktopDevToolsSession::TrustedKeyParams(input, true), &second, timeout);
  if (up.ok && output) *output = {{"trusted", true}};
  return up;
}

BrowserControlResult DesktopEngine::GetDialog(TabLease lease, Json* dialog, Timeout timeout) {
  if (!dialog) return BrowserControlResult::Failure("INTERNAL", "dialog is required");
  auto state = std::make_shared<Json>();
  const auto result = impl_->RunOnUi([this, lease, state] {
    auto* tab = impl_->FindTab(lease);
    if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist or is stale");
    *state = tab->dialogs.Current(tab->browser);
    return BrowserControlResult::Success(impl_->Snapshot(*tab));
  }, timeout);
  if (result.ok) *dialog = *state;
  return result;
}

BrowserControlResult DesktopEngine::HandleDialog(TabLease lease, const Json& action, Json* output, Timeout timeout) {
  auto state = std::make_shared<Json>();
  const auto result = impl_->RunOnUi([this, lease, action, state] {
    auto* tab = impl_->FindTab(lease);
    if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist or is stale");
    if (!tab->dialogs.Handle(tab->browser, action, state.get())) {
      return BrowserControlResult::Failure("UNSUPPORTED", "No matching JavaScript dialog is open");
    }
    return BrowserControlResult::Success(impl_->Snapshot(*tab));
  }, timeout);
  if (result.ok && output) *output = *state;
  return result;
}

BrowserControlResult DesktopEngine::DevTools(TabLease lease, std::string method, const Json& params,
                                             Json* output, Timeout timeout) {
  if (!output) return BrowserControlResult::Failure("INTERNAL", "result is required");
  auto pending = std::make_shared<PendingDevTools>();
  const auto started = impl_->RunOnUi([this, lease, method = std::move(method), params, pending] {
    auto* tab = impl_->FindTab(lease);
    if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist or is stale");
    pending->session = tab->devtools;
    pending->operation = pending->session->Begin(tab->browser, method, params);
    return BrowserControlResult::Success(impl_->Snapshot(*tab));
  }, timeout);
  if (!started.ok) return started;
  const auto completed = pending->session->Wait(pending->operation, timeout);
  const auto result = DevToolsResult(completed);
  if (result.ok) *output = completed.value;
  return result;
}

}  // namespace kelpie
