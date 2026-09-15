#include "desktop_engine_impl.h"

#include <condition_variable>
#include <ctime>
#include <iomanip>
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

DesktopBrowserControl::Timeout RemainingTimeout(std::chrono::steady_clock::time_point started,
                                                DesktopBrowserControl::Timeout timeout) {
  const auto elapsed = std::chrono::duration_cast<DesktopBrowserControl::Timeout>(
      std::chrono::steady_clock::now() - started);
  return elapsed >= timeout ? DesktopBrowserControl::Timeout::zero() : timeout - elapsed;
}

std::optional<double> CookieExpirySeconds(const Json& value) {
  if (value.is_number()) return value.get<double>();
  if (!value.is_string()) return std::nullopt;
  std::tm utc{};
  std::istringstream stream(value.get<std::string>());
  stream >> std::get_time(&utc, "%Y-%m-%dT%H:%M:%SZ");
  if (stream.fail() || stream.peek() != std::char_traits<char>::eof()) return std::nullopt;
#if defined(_WIN32)
  const std::time_t seconds = _mkgmtime(&utc);
#else
  const std::time_t seconds = timegm(&utc);
#endif
  if (seconds < 0) return std::nullopt;
  return static_cast<double>(seconds);
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
  if (!initialized || shutting_down) return BrowserControlResult::Failure("INTERNAL", "Browser runtime is not running");
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
  const auto impl = impl_;
  if (!output) return BrowserControlResult::Failure("INTERNAL", "tabs is required");
  auto collected = std::make_shared<std::vector<TabSnapshot>>();
  const auto result = impl->RunOnUi([impl, collected] {
    collected->clear();
    for (const auto& tab : impl->tabs) collected->push_back(impl->Snapshot(tab));
    return BrowserControlResult::Success(impl->ActiveTab() ? std::optional(impl->Snapshot(*impl->ActiveTab())) : std::nullopt);
  }, timeout);
  if (result.ok) *output = *collected;
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
      for (auto& candidate : impl->tabs) if (candidate.id == *tab_id) { tab = &candidate; break; }
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

BrowserControlResult DesktopEngine::CreateTab(std::string url, TabSnapshot* tab, Timeout timeout) {
  const auto impl = impl_;
  auto created = std::make_shared<TabSnapshot>();
  const auto result = impl->RunOnUi([impl, url = std::move(url), created] {
    return impl->CreateTabOnUi(url, created.get());
  }, timeout);
  if (result.ok && tab) *tab = *created;
  return result;
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
    CefRefPtr<CefBrowser> closing = tab->browser;
    CefRefPtr<DesktopDevToolsSession> closing_devtools = tab->devtools;
    const bool was_active = impl->browser && impl->browser->IsSame(closing);
    if (impl->tabs.size() == 1) {
      TabSnapshot replacement;
      const auto created = impl->CreateTabOnUi("about:blank", &replacement);
      if (!created.ok) return created;
      impl->browser = impl->tabs.back().browser;
    } else if (was_active) {
      for (const auto& candidate : impl->tabs) {
        if (!candidate.browser->IsSame(closing)) { impl->browser = candidate.browser; break; }
      }
    }
    if (closing_devtools) closing_devtools->CancelAll();
#if defined(_WIN32)
    if (was_active && impl->browser && impl->browser->GetHost()) {
      ShowWindow(impl->browser->GetHost()->GetWindowHandle(), SW_SHOW);
    }
#endif
    impl->tabs.erase(std::remove_if(impl->tabs.begin(), impl->tabs.end(),
        [&closing](const DesktopEngine::Impl::Tab& candidate) { return candidate.browser->IsSame(closing); }),
        impl->tabs.end());
    closing->GetHost()->CloseBrowser(false);
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
  const auto result = impl->RunOnUi([impl, lease, state] { auto* target=impl->FindTab(lease); if(!target) return BrowserControlResult::Failure("TAB_NOT_FOUND","The tab does not exist or is stale"); target->browser->GoBack(); *state=impl->Snapshot(*target); return BrowserControlResult::Success(*state); }, timeout);
  if (result.ok && tab) *tab=*state; return result;
}
BrowserControlResult DesktopEngine::Forward(TabLease lease, TabSnapshot* tab, Timeout timeout) {
  const auto impl = impl_;
  auto state = std::make_shared<TabSnapshot>();
  const auto result = impl->RunOnUi([impl, lease, state] { auto* target=impl->FindTab(lease); if(!target) return BrowserControlResult::Failure("TAB_NOT_FOUND","The tab does not exist or is stale"); target->browser->GoForward(); *state=impl->Snapshot(*target); return BrowserControlResult::Success(*state); }, timeout);
  if (result.ok && tab) *tab=*state; return result;
}
BrowserControlResult DesktopEngine::Reload(TabLease lease, TabSnapshot* tab, Timeout timeout) {
  const auto impl = impl_;
  auto state = std::make_shared<TabSnapshot>();
  const auto result = impl->RunOnUi([impl, lease, state] { auto* target=impl->FindTab(lease); if(!target) return BrowserControlResult::Failure("TAB_NOT_FOUND","The tab does not exist or is stale"); target->browser->Reload(); *state=impl->Snapshot(*target); return BrowserControlResult::Success(*state); }, timeout);
  if (result.ok && tab) *tab=*state; return result;
}
BrowserControlResult DesktopEngine::StopLoading(TabLease lease, TabSnapshot* tab, Timeout timeout) {
  const auto impl = impl_;
  auto state = std::make_shared<TabSnapshot>();
  const auto result = impl->RunOnUi([impl, lease, state] { auto* target=impl->FindTab(lease); if(!target) return BrowserControlResult::Failure("TAB_NOT_FOUND","The tab does not exist or is stale"); target->browser->StopLoad(); *state=impl->Snapshot(*target); return BrowserControlResult::Success(*state); }, timeout);
  if (result.ok && tab) *tab=*state; return result;
}

BrowserControlResult DesktopEngine::Evaluate(TabLease lease, std::string script, Json* value, Timeout timeout) {
  const auto impl = impl_;
  if (value == nullptr) return BrowserControlResult::Failure("INTERNAL", "result is required");
  const auto started_at = std::chrono::steady_clock::now();
  auto pending = std::make_shared<PendingDevTools>();
  const auto started = impl->RunOnUi([impl, lease, script = std::move(script), pending] {
    auto* tab = impl->FindTab(lease);
    if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist or is stale");
    pending->session = tab->devtools;
    pending->operation = pending->session->Begin(tab->browser, "Runtime.evaluate",
                                                  DesktopDevToolsSession::EvaluateParams(script));
    return BrowserControlResult::Success(impl->Snapshot(*tab));
  }, timeout);
  if (!started.ok) return started;
  const auto parsed = DesktopDevToolsSession::ParseEvaluateResult(
      pending->session->Wait(pending->operation, RemainingTimeout(started_at, timeout)));
  const auto result = DevToolsResult(parsed);
  if (result.ok) *value = parsed.value;
  return result;
}

BrowserControlResult DesktopEngine::Screenshot(TabLease lease, BrowserScreenshot* image, Timeout timeout) {
  const auto impl = impl_;
  if (image == nullptr) return BrowserControlResult::Failure("INTERNAL", "image is required");
  const auto screenshot_params = DesktopDevToolsSession::ScreenshotParams(Json::object());
  if (!screenshot_params) return BrowserControlResult::Failure("INTERNAL", "Screenshot parameters are invalid");
  const auto started_at = std::chrono::steady_clock::now();
  auto pending = std::make_shared<PendingDevTools>();
  const auto started = impl->RunOnUi([impl, lease, pending, screenshot_params] {
    auto* tab = impl->FindTab(lease);
    if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist or is stale");
    pending->session = tab->devtools;
    pending->operation = pending->session->Begin(tab->browser, "Page.captureScreenshot",
                                                  *screenshot_params);
    return BrowserControlResult::Success(impl->Snapshot(*tab));
  }, timeout);
  if (!started.ok) return started;
  const auto parsed = DesktopDevToolsSession::ParseScreenshotResult(
      pending->session->Wait(pending->operation, RemainingTimeout(started_at, timeout)));
  const auto result = DevToolsResult(parsed);
  if (result.ok) {
    image->mime_type = parsed.value.value("mimeType", "image/png");
    image->base64_data = parsed.value.value("data", "");
  }
  return result;
}
BrowserControlResult DesktopEngine::GetCookies(TabLease lease, const Json& query, Json* cookies, Timeout timeout) {
  if (!cookies) return BrowserControlResult::Failure("INTERNAL", "cookies is required");
  Json response;
  const auto result = DevTools(lease, "Network.getAllCookies", Json::object(), &response, timeout);
  if (!result.ok) return result;
  const std::string url = query.value("url", "");
  const std::string domain = query.value("domain", "");
  const std::string name = query.value("name", "");
  Json filtered = Json::array();
  for (const auto& cookie : response.value("cookies", Json::array())) {
    if (!url.empty() && cookie.value("domain", "").empty()) continue;
    if (!domain.empty() && cookie.value("domain", "") != domain) continue;
    if (!name.empty() && cookie.value("name", "") != name) continue;
    filtered.push_back(cookie);
  }
  *cookies = std::move(filtered);
  return result;
}

BrowserControlResult DesktopEngine::SetCookies(TabLease lease, const Json& cookies, Json* output, Timeout timeout) {
  const Json values = cookies.is_array() ? cookies : Json::array({cookies});
  if (values.empty()) return BrowserControlResult::Failure("INVALID_URL", "At least one cookie is required");
  const auto started_at = std::chrono::steady_clock::now();
  std::size_t set = 0;
  for (auto cookie : values) {
    if (!cookie.is_object() || !cookie.contains("name") || !cookie["name"].is_string() ||
        (!cookie.contains("url") && !cookie.contains("domain"))) {
      return BrowserControlResult::Failure("INVALID_URL", "Cookies require name and url or domain");
    }
    if (cookie.contains("sameSite") && cookie["sameSite"].is_string()) {
      std::string value = cookie["sameSite"].get<std::string>();
      std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
      if (value == "lax") cookie["sameSite"] = "Lax";
      else if (value == "strict") cookie["sameSite"] = "Strict";
      else if (value == "none" || value == "no_restriction") cookie["sameSite"] = "None";
      else return BrowserControlResult::Failure("INVALID_URL", "Invalid sameSite value");
    }
    if (cookie.contains("expires")) {
      const auto expiry = CookieExpirySeconds(cookie["expires"]);
      if (!expiry) return BrowserControlResult::Failure("INVALID_URL", "Cookie expires must be epoch seconds or ISO-8601 UTC");
      cookie["expires"] = *expiry;
    }
    Json response;
    const auto result = DevTools(lease, "Network.setCookie", cookie, &response,
                                 RemainingTimeout(started_at, timeout));
    if (!result.ok) return result;
    if (!response.value("success", false)) return BrowserControlResult::Failure("INTERNAL", "CEF rejected the cookie");
    ++set;
  }
  if (output) *output = {{"set", set}};
  return BrowserControlResult::Success();
}

BrowserControlResult DesktopEngine::DeleteCookies(TabLease lease, const Json& query, Json* output, Timeout timeout) {
  const auto started_at = std::chrono::steady_clock::now();
  if (query.value("deleteAll", false)) {
    Json response;
    const auto result = DevTools(lease, "Network.clearBrowserCookies", Json::object(), &response, timeout);
    if (result.ok && output) *output = {{"deleted", "all"}};
    return result;
  }
  if (!query.contains("name") || !query["name"].is_string()) {
    return BrowserControlResult::Failure("INVALID_URL", "Cookie deletion requires name or deleteAll");
  }
  Json params{{"name", query["name"]}};
  for (const char* field : {"url", "domain", "path"}) if (query.contains(field)) params[field] = query[field];
  if (!params.contains("url") && !params.contains("domain")) {
    return BrowserControlResult::Failure("INVALID_URL", "Cookie deletion requires url or domain");
  }
  Json response;
  const auto result = DevTools(lease, "Network.deleteCookies", params, &response,
                               RemainingTimeout(started_at, timeout));
  if (result.ok && output) *output = {{"deleted", 1}};
  return result;
}

BrowserControlResult DesktopEngine::DispatchTrustedInput(TabLease lease, const Json& input, Json* output, Timeout timeout) {
  const std::string type = input.value("type", "");
  if (type == "key") {
    const auto started = std::chrono::steady_clock::now();
    Json ignored;
    auto result = DevTools(lease, "Input.dispatchKeyEvent", DesktopDevToolsSession::TrustedKeyParams(input, false),
                           &ignored, RemainingTimeout(started, timeout));
    if (!result.ok) return result;
    result = DevTools(lease, "Input.dispatchKeyEvent", DesktopDevToolsSession::TrustedKeyParams(input, true),
                      &ignored, RemainingTimeout(started, timeout));
    if (result.ok && output) *output = {{"trusted", true}};
    return result;
  }
  if (type != "click" && type != "fill" && type != "type" && type != "selectOption" && type != "setChecked") {
    return BrowserControlResult::Failure("UNSUPPORTED", "Unsupported native input type");
  }
  const std::string selector = input.value("selector", "");
  if (selector.empty() && type != "type") return BrowserControlResult::Failure("INVALID_URL", "selector is required");
  const auto started = std::chrono::steady_clock::now();
  Json target;
  if (!selector.empty()) {
    const std::string selector_json = Json(selector).dump();
    const std::string script = "(()=>{const e=document.querySelector(" + selector_json + ");if(!e)return null;"
      "e.scrollIntoView({block:'center',inline:'center'});const r=e.getBoundingClientRect();const cs=getComputedStyle(e);"
      "const visible=r.width>0&&r.height>0&&cs.visibility!=='hidden'&&cs.display!=='none'&&!e.disabled;"
      "return {x:r.left+r.width/2,y:r.top+r.height/2,visible,type:(e.type||e.tagName).toLowerCase(),"
      "checked:!!e.checked,value:e.value||'',options:e.tagName==='SELECT'?Array.from(e.options).map(o=>o.value):[]};})()";
    auto result = Evaluate(lease, script, &target, RemainingTimeout(started, timeout));
    if (!result.ok) return result;
    if (!target.is_object() || !target.value("visible", false)) return BrowserControlResult::Failure("TAB_NOT_FOUND", "No matching enabled visible element exists");
  }
  auto mouse_click = [&](Json& ignored) {
    auto result = DevTools(lease, "Input.dispatchMouseEvent", {{"type","mousePressed"},{"x",target["x"]},{"y",target["y"]},{"button","left"},{"clickCount",1}}, &ignored, RemainingTimeout(started, timeout));
    if (!result.ok) return result;
    return DevTools(lease, "Input.dispatchMouseEvent", {{"type","mouseReleased"},{"x",target["x"]},{"y",target["y"]},{"button","left"},{"clickCount",1}}, &ignored, RemainingTimeout(started, timeout));
  };
  Json ignored;
  if (type == "click") { auto result = mouse_click(ignored); if (result.ok && output) *output={{"trusted",true}}; return result; }
  if (type == "setChecked") {
    if (target.value("type", "") != "checkbox") return BrowserControlResult::Failure("UNSUPPORTED", "setChecked requires a checkbox");
    const bool wanted = input.value("checked", false);
    if (target.value("checked", false) != wanted) { auto result=mouse_click(ignored); if(!result.ok) return result; }
    if (output) *output={{"trusted",true},{"checked",wanted}}; return BrowserControlResult::Success();
  }
  if (type == "selectOption") {
    if (target.value("type", "") != "select") return BrowserControlResult::Failure("UNSUPPORTED", "selectOption requires a select element");
    const std::string wanted=input.value("value", ""); const auto options=target.value("options", Json::array());
    auto it=std::find(options.begin(),options.end(),Json(wanted));
    if (it==options.end()) return BrowserControlResult::Failure("INVALID_URL", "The requested option does not exist");
    if (target.value("value", "") == wanted) { if(output)*output={{"trusted",true},{"value",wanted}}; return BrowserControlResult::Success(); }
    auto result=mouse_click(ignored); if(!result.ok)return result;
    const int index=static_cast<int>(std::distance(options.begin(),it));
    for (int i=0;i<index;++i) { Json key{{"type","keyDown"},{"key","ArrowDown"},{"code","ArrowDown"}}; result=DevTools(lease,"Input.dispatchKeyEvent",key,&ignored,RemainingTimeout(started,timeout)); if(!result.ok)return result; }
    result=DevTools(lease,"Input.dispatchKeyEvent",{{"type","keyDown"},{"key","Enter"},{"code","Enter"}},&ignored,RemainingTimeout(started,timeout));
    if(result.ok&&output)*output={{"trusted",true},{"value",wanted}}; return result;
  }
  if (!selector.empty()) { auto result=mouse_click(ignored); if(!result.ok)return result; }
  const std::string text=type=="fill"?input.value("value",""):input.value("text","");
  if (type == "fill") {
    auto result=DevTools(lease,"Input.dispatchKeyEvent",{{"type","keyDown"},{"key","a"},{"code","KeyA"},{"modifiers",2}},&ignored,RemainingTimeout(started,timeout)); if(!result.ok)return result;
    result=DevTools(lease,"Input.dispatchKeyEvent",{{"type","keyDown"},{"key","Backspace"},{"code","Backspace"}},&ignored,RemainingTimeout(started,timeout)); if(!result.ok)return result;
  }
  auto result=DevTools(lease,"Input.insertText",{{"text",text}},&ignored,RemainingTimeout(started,timeout));
  if(result.ok&&output)*output={{"trusted",true},{"text",text}}; return result;
}

BrowserControlResult DesktopEngine::GetDialog(TabLease lease, Json* dialog, Timeout timeout) {
  const auto impl = impl_;
  if (!dialog) return BrowserControlResult::Failure("INTERNAL", "dialog is required");
  auto state = std::make_shared<Json>();
  const auto result = impl->RunOnUi([impl, lease, state] {
    auto* tab = impl->FindTab(lease);
    if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist or is stale");
    *state = tab->dialogs.Current(tab->browser);
    return BrowserControlResult::Success(impl->Snapshot(*tab));
  }, timeout);
  if (result.ok) *dialog = *state;
  return result;
}

BrowserControlResult DesktopEngine::HandleDialog(TabLease lease, const Json& action, Json* output, Timeout timeout) {
  const auto impl = impl_;
  auto state = std::make_shared<Json>();
  const auto result = impl->RunOnUi([impl, lease, action, state] {
    auto* tab = impl->FindTab(lease);
    if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist or is stale");
    if (!tab->dialogs.Handle(tab->browser, action, state.get())) {
      return BrowserControlResult::Failure("UNSUPPORTED", "No matching JavaScript dialog is open");
    }
    return BrowserControlResult::Success(impl->Snapshot(*tab));
  }, timeout);
  if (result.ok && output) *output = *state;
  return result;
}

BrowserControlResult DesktopEngine::DevTools(TabLease lease, std::string method, const Json& params,
                                             Json* output, Timeout timeout) {
  const auto impl = impl_;
  if (!output) return BrowserControlResult::Failure("INTERNAL", "result is required");
  const auto started_at = std::chrono::steady_clock::now();
  auto pending = std::make_shared<PendingDevTools>();
  const auto started = impl->RunOnUi([impl, lease, method = std::move(method), params, pending] {
    auto* tab = impl->FindTab(lease);
    if (!tab) return BrowserControlResult::Failure("TAB_NOT_FOUND", "The tab does not exist or is stale");
    pending->session = tab->devtools;
    pending->operation = pending->session->Begin(tab->browser, method, params);
    return BrowserControlResult::Success(impl->Snapshot(*tab));
  }, timeout);
  if (!started.ok) return started;
  const auto completed = pending->session->Wait(pending->operation, RemainingTimeout(started_at, timeout));
  const auto result = DevToolsResult(completed);
  if (result.ok) *output = completed.value;
  return result;
}

}  // namespace kelpie
