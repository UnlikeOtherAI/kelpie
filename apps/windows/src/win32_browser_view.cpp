#include "win32_browser_view.h"

#include <string>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#if defined(HAS_CEF)
#include "include/base/cef_bind.h"
#include "include/cef_app.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_display_handler.h"
#include "include/cef_load_handler.h"
#include "include/cef_life_span_handler.h"
#endif

namespace kelpie::windows {
namespace {

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return {};
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  std::wstring output(static_cast<std::size_t>(size > 0 ? size - 1 : 0), L'\0');
  if (size > 1) {
    MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, output.data(), size - 1);
  }
  return output;
}

#if defined(HAS_CEF)
class ClientBridge final : public CefClient,
                           public CefDisplayHandler,
                           public CefLifeSpanHandler,
                           public CefLoadHandler {
 public:
  explicit ClientBridge(Win32BrowserView* owner) : owner_(owner) {}

  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }

  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    browser_ = browser;
    owner_->ShowFallback(false);
    owner_->UpdateState({browser->GetMainFrame()->GetURL(), "", false, false, false});
    const std::string target_url = owner_->CurrentUrl();
    if (!target_url.empty() && target_url != "about:blank") {
      browser->GetMainFrame()->LoadURL(target_url);
    }
  }

  void OnTitleChange(CefRefPtr<CefBrowser>, const CefString& title) override {
    BrowserState state = owner_->state();
    state.title = title.ToString();
    owner_->UpdateState(state);
  }

  void OnAddressChange(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, const CefString& url) override {
    if (!frame->IsMain()) {
      return;
    }
    BrowserState state = owner_->state();
    state.url = url.ToString();
    owner_->UpdateState(state);
  }

  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                            bool is_loading,
                            bool can_go_back,
                            bool can_go_forward) override {
    BrowserState state = owner_->state();
    state.is_loading = is_loading;
    state.can_go_back = can_go_back;
    state.can_go_forward = can_go_forward;
    if (!browser->GetMainFrame()->GetURL().empty()) {
      state.url = browser->GetMainFrame()->GetURL();
    }
    owner_->UpdateState(state);
  }

  CefRefPtr<CefBrowser> browser() const { return browser_; }

 private:
  Win32BrowserView* owner_;
  CefRefPtr<CefBrowser> browser_;

  IMPLEMENT_REFCOUNTING(ClientBridge);
};
#endif

}  // namespace

Win32BrowserView::Win32BrowserView() = default;

Win32BrowserView::~Win32BrowserView() {
  Destroy();
}

bool Win32BrowserView::Create(HWND parent, HINSTANCE instance, const RECT& bounds,
                              BrowserStateObserver* observer) {
  observer_ = observer;
  hwnd_ = CreateWindowExW(0, L"STATIC", L"", WS_CHILD | WS_VISIBLE,
                          bounds.left, bounds.top, bounds.right - bounds.left,
                          bounds.bottom - bounds.top, parent, nullptr, instance, nullptr);
  if (hwnd_ == nullptr) {
    return false;
  }

  fallback_label_ = CreateWindowExW(0, L"STATIC", L"Chromium runtime unavailable",
                                    WS_CHILD | WS_VISIBLE | SS_CENTER,
                                    0, 0, bounds.right - bounds.left, bounds.bottom - bounds.top,
                                    hwnd_, nullptr, instance, nullptr);

#if defined(HAS_CEF)
  auto client = CefRefPtr<ClientBridge>(new ClientBridge(this));
  client_bridge_ = client.get();
  CefWindowInfo window_info;
  RECT child_bounds{0, 0, bounds.right - bounds.left, bounds.bottom - bounds.top};
  window_info.SetAsChild(hwnd_, child_bounds);
  CefBrowserSettings settings;
  CefBrowserHost::CreateBrowser(window_info, client, "about:blank", settings, nullptr, nullptr);
#endif
  return true;
}

void Win32BrowserView::Destroy() {
#if defined(HAS_CEF)
  auto* client = reinterpret_cast<ClientBridge*>(client_bridge_);
  if (client != nullptr && client->browser() != nullptr) {
    client->browser()->GetHost()->CloseBrowser(true);
  }
#endif
  if (hwnd_ != nullptr) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
}

void Win32BrowserView::Resize(const RECT& bounds) {
  if (hwnd_ == nullptr) {
    return;
  }
  SetWindowPos(hwnd_, nullptr, bounds.left, bounds.top, bounds.right - bounds.left,
               bounds.bottom - bounds.top, SWP_NOZORDER);
  if (fallback_label_ != nullptr) {
    SetWindowPos(fallback_label_, nullptr, 0, 0, bounds.right - bounds.left, bounds.bottom - bounds.top,
                 SWP_NOZORDER);
  }
}

void Win32BrowserView::Focus() {
  if (hwnd_ != nullptr) {
    SetFocus(hwnd_);
  }
}

BrowserState Win32BrowserView::state() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return state_;
}

bool Win32BrowserView::HasNativeBrowser() const {
#if defined(HAS_CEF)
  return true;
#else
  return false;
#endif
}

std::string Win32BrowserView::EvaluateJs(const std::string&) {
  return {};
}

std::vector<std::uint8_t> Win32BrowserView::TakeSnapshot() {
  return {};
}

void Win32BrowserView::LoadUrl(const std::string& url) {
#if defined(HAS_CEF)
  auto* client = reinterpret_cast<ClientBridge*>(client_bridge_);
  if (client != nullptr && client->browser() != nullptr) {
    client->browser()->GetMainFrame()->LoadURL(url);
    return;
  }
#endif
  BrowserState next = state();
  next.url = url;
  next.title = url;
  next.is_loading = false;
  UpdateState(next);
  UpdateFallbackText(Utf8ToWide(url));
}

std::string Win32BrowserView::CurrentUrl() const {
  return state().url;
}

std::string Win32BrowserView::CurrentTitle() const {
  return state().title;
}

bool Win32BrowserView::IsLoading() const {
  return state().is_loading;
}

bool Win32BrowserView::CanGoBack() const {
  return state().can_go_back;
}

bool Win32BrowserView::CanGoForward() const {
  return state().can_go_forward;
}

void Win32BrowserView::GoBack() {
#if defined(HAS_CEF)
  auto* client = reinterpret_cast<ClientBridge*>(client_bridge_);
  if (client != nullptr && client->browser() != nullptr) {
    client->browser()->GoBack();
  }
#endif
}

void Win32BrowserView::GoForward() {
#if defined(HAS_CEF)
  auto* client = reinterpret_cast<ClientBridge*>(client_bridge_);
  if (client != nullptr && client->browser() != nullptr) {
    client->browser()->GoForward();
  }
#endif
}

void Win32BrowserView::Reload() {
#if defined(HAS_CEF)
  auto* client = reinterpret_cast<ClientBridge*>(client_bridge_);
  if (client != nullptr && client->browser() != nullptr) {
    client->browser()->Reload();
  }
#endif
}

void Win32BrowserView::UpdateState(BrowserState state) {
  BrowserState snapshot;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    state_ = std::move(state);
    snapshot = state_;
  }
  if (observer_ != nullptr) {
    observer_->OnBrowserStateChanged(snapshot);
  }
}

void Win32BrowserView::ShowFallback(bool visible) const {
  if (fallback_label_ != nullptr) {
    ShowWindow(fallback_label_, visible ? SW_SHOW : SW_HIDE);
  }
}

void Win32BrowserView::UpdateFallbackText(const std::wstring& message) const {
  if (fallback_label_ != nullptr) {
    SetWindowTextW(fallback_label_, message.c_str());
  }
}

}  // namespace kelpie::windows
