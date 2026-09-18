#include <algorithm>
#include <string>

#if defined(_WIN32)
#include <windows.h>
#endif

#include "include/cef_task.h"
#include "include/cef_version.h"
#include "kelpie/favicon_registry.h"

#include "desktop_cef_client.h"

namespace {

#if defined(_WIN32)
// A tab browser window is a child of the single application shell window, so
// CEF's default close notification -- PostMessage(WM_CLOSE) to
// GetAncestor(tab_window, GA_ROOT) -- would land on the application window and
// read as a request to close the whole application. Closing a tab must destroy
// only that tab's own host window.
class DestroyTabHostWindowTask final : public CefTask {
 public:
  explicit DestroyTabHostWindowTask(HWND window) : window_(window) {}

  void Execute() override {
    if (window_ != nullptr && ::IsWindow(window_)) ::DestroyWindow(window_);
  }

 private:
  HWND window_ = nullptr;
  IMPLEMENT_REFCOUNTING(DestroyTabHostWindowTask);
};
#endif

}  // namespace

// Chromium event handling for the desktop engine.
//
// `desktop_engine.cpp` owns the engine's own lifecycle — CefInitialize, the
// message pump, shutdown. This file owns what Chromium calls back into: browser
// creation and close, loading and navigation state, dialogs, and the offscreen
// paint buffer. Favicon capture is the third piece, in
// `desktop_engine_favicon.cpp`.
namespace kelpie {

void DesktopCefClient::OnAfterCreated(CefRefPtr<CefBrowser> browser) {
  if (owner_->browser == nullptr) {
    owner_->browser = browser;
  }
  if (auto* tab = owner_->FindTab(browser)) {
    tab->url = browser->GetMainFrame() ? browser->GetMainFrame()->GetURL().ToString()
                                       : std::string("about:blank");
  }
  owner_->UpdateActiveState();
}

bool DesktopCefClient::OnBeforePopup(CefRefPtr<CefBrowser>,
                                     CefRefPtr<CefFrame>,
#if CEF_VERSION_MAJOR >= 130
                                     int,
#endif
                                     const CefString& target_url,
                                     const CefString&,
                                     WindowOpenDisposition,
                                     bool,
                                     const CefPopupFeatures&,
                                     CefWindowInfo&,
                                     CefRefPtr<CefClient>&,
                                     CefBrowserSettings&,
                                     CefRefPtr<CefDictionaryValue>&,
                                     bool*) {
  const std::string url = target_url.ToString();
  if (url.empty()) return true;
  TabSnapshot created;
  const auto result = owner_->CreateTabOnUi(url, &created);
  if (!result.ok) return true;
  if (auto* tab = owner_->FindTab(TabLease{created.id, created.generation})) {
#if defined(_WIN32)
    if (owner_->browser && owner_->browser->GetHost()) ShowWindow(owner_->browser->GetHost()->GetWindowHandle(), SW_HIDE);
    if (tab->browser && tab->browser->GetHost()) ShowWindow(tab->browser->GetHost()->GetWindowHandle(), SW_SHOW);
#endif
    owner_->browser = tab->browser;
    owner_->UpdateActiveState();
  }
  return true;
}

bool DesktopCefClient::DoClose(CefRefPtr<CefBrowser> browser) {
#if defined(_WIN32)
  // Returning false here lets CEF send the OS close notification to the tab
  // window's top-level owner, which is the shared application shell window --
  // one tab closing would then drain the control listener and shut the runtime
  // down. Take ownership of the tab window instead so the close stays scoped to
  // the tab that asked for it.
  if (browser && browser->GetHost()) {
    const HWND window = browser->GetHost()->GetWindowHandle();
    if (window != nullptr) {
      // CEF rewrites this browser's destruction state after DoClose returns, so
      // the window must be destroyed after the call unwinds, not inside it.
      CefPostTask(TID_UI, CefRefPtr<CefTask>(new DestroyTabHostWindowTask(window)));
      return true;
    }
  }
#endif
  (void)browser;
  return false;
}

void DesktopCefClient::OnBeforeClose(CefRefPtr<CefBrowser> browser) {
  for (auto& tab : owner_->tabs) {
    if (tab.browser && tab.browser->IsSame(browser) && tab.devtools) tab.devtools->CancelAll();
  }
  owner_->tabs.erase(std::remove_if(owner_->tabs.begin(), owner_->tabs.end(),
      [&browser](const DesktopEngine::Impl::Tab& tab) { return tab.browser->IsSame(browser); }),
      owner_->tabs.end());
  if (owner_->browser && owner_->browser->IsSame(browser)) {
    owner_->browser = nullptr;
    for (const auto& candidate : owner_->tabs) {
      if (!candidate.closing) {
        owner_->browser = candidate.browser;
#if defined(_WIN32)
        if (owner_->browser && owner_->browser->GetHost()) {
          ShowWindow(owner_->browser->GetHost()->GetWindowHandle(), SW_SHOW);
        }
#endif
        break;
      }
    }
  }
  owner_->UpdateActiveState();
}

void DesktopCefClient::OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                                            bool is_loading,
                                            bool can_go_back,
                                            bool can_go_forward) {
  if (auto* tab = owner_->FindTab(browser)) {
    tab->loading = is_loading;
    tab->can_go_back = can_go_back;
    tab->can_go_forward = can_go_forward;
    if (!is_loading && tab->navigation_requested > tab->navigation_completed && tab->navigation_error.empty()) {
      tab->navigation_completed = tab->navigation_requested;
    }
  }
  owner_->UpdateActiveState();
}

void DesktopCefClient::OnLoadEnd(CefRefPtr<CefBrowser> browser,
                                 CefRefPtr<CefFrame> frame,
                                 int) {
  if (!frame || !frame->IsMain()) {
    return;
  }
  if (auto* tab = owner_->FindTab(browser)) {
    tab->url = frame->GetURL().ToString();
    if (owner_->navigation_sink) owner_->navigation_sink(tab->url, tab->title);
  }
  owner_->UpdateActiveState();
}

void DesktopCefClient::OnLoadError(CefRefPtr<CefBrowser> browser,
                                   CefRefPtr<CefFrame> frame,
                                   CefLoadHandler::ErrorCode,
                                   const CefString& error_text,
                                   const CefString&) {
  if (!frame || !frame->IsMain()) return;
  if (auto* tab = owner_->FindTab(browser)) {
    tab->loading = false;
    tab->navigation_error = error_text.ToString();
  }
  owner_->UpdateActiveState();
}

void DesktopCefClient::OnAddressChange(CefRefPtr<CefBrowser> browser,
                                       CefRefPtr<CefFrame> frame,
                                       const CefString& url) {
  if (!frame || !frame->IsMain()) return;
  if (auto* tab = owner_->FindTab(browser)) {
    const std::string next = url.ToString();
    // A new document has no icon until OnFaviconURLChange fires. Keeping the old
    // one would leave the previous site's favicon on the pill; the registry
    // still holds it, keyed by that site's host.
    if (FaviconRegistry::HostForUrl(next) != FaviconRegistry::HostForUrl(tab->url)) {
      tab->favicon_url.clear();
      tab->favicon_png_base64.reset();
    }
    tab->url = next;
    if (owner_->navigation_sink) owner_->navigation_sink(tab->url, tab->title);
  }
  owner_->UpdateActiveState();
}

void DesktopCefClient::OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString& title) {
  if (auto* tab = owner_->FindTab(browser)) {
    tab->title = title.ToString();
    if (owner_->navigation_sink) owner_->navigation_sink(tab->url, tab->title);
  }
  owner_->UpdateActiveState();
}

bool DesktopCefClient::OnConsoleMessage(CefRefPtr<CefBrowser>,
                                        cef_log_severity_t level,
                                        const CefString& message,
                                        const CefString& source,
                                        int line) {
  if (!owner_->console_sink) {
    return false;
  }

  std::string level_name = "log";
  if (level == LOGSEVERITY_WARNING) {
    level_name = "warn";
  } else if (level == LOGSEVERITY_ERROR || level == LOGSEVERITY_FATAL) {
    level_name = "error";
  } else if (level == LOGSEVERITY_INFO) {
    level_name = "info";
  }

  owner_->console_sink({
      {"level", level_name},
      {"text", message.ToString()},
      {"source", source.ToString()},
      {"line", line},
      {"column", 0},
  });
  return false;
}

bool DesktopCefClient::OnJSDialog(CefRefPtr<CefBrowser> browser,
                                      const CefString& origin_url,
                                      cef_jsdialog_type_t dialog_type,
                                      const CefString& message_text,
                                      const CefString& default_prompt_text,
                                      CefRefPtr<CefJSDialogCallback> callback,
                                      bool& suppress_message) {
  suppress_message = false;
  if (auto* tab = owner_->FindTab(browser)) {
    return tab->dialogs.Observe(browser, dialog_type, origin_url, message_text,
                                default_prompt_text, callback);
  }
  return false;
}

void DesktopCefClient::OnResetDialogState(CefRefPtr<CefBrowser> browser) {
  if (auto* tab = owner_->FindTab(browser)) tab->dialogs.Reset(browser);
}

void DesktopCefClient::GetViewRect(CefRefPtr<CefBrowser>, CefRect& rect) {
  rect = CefRect(0, 0, owner_->viewport.width, owner_->viewport.height);
}

void DesktopCefClient::OnPaint(CefRefPtr<CefBrowser>,
                               PaintElementType,
                               const RectList&,
                               const void* buffer,
                               int width,
                               int height) {
  if (buffer == nullptr || width <= 0 || height <= 0) {
    return;
  }
  const std::size_t size = static_cast<std::size_t>(width) * static_cast<std::size_t>(height) * 4U;
  std::lock_guard<std::mutex> lock(owner_->mutex);
  owner_->snapshot_bytes.assign(static_cast<const std::uint8_t*>(buffer),
                                static_cast<const std::uint8_t*>(buffer) + size);
}

}  // namespace kelpie
