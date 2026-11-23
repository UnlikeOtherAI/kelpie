#include <algorithm>
#include <string>

#if defined(_WIN32)
#include <windows.h>
#endif

#include "include/cef_task.h"
#include "include/cef_parser.h"
#include "include/cef_version.h"
#include "kelpie/favicon_registry.h"
#include "new_window_policy.h"

#include "desktop_cef_client.h"

namespace {

std::string PopupTitle(const CefString& url) {
  CefURLParts parts;
  if (!CefParseURL(url, parts)) return "Pop-up";
  const CefString scheme(&parts.scheme);
  if (scheme != "https" && scheme != "http") return "Pop-up";
  return CefString(&parts.origin).ToString();
}

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
  if (opener_ != 0) {
    owner_->popups.push_back({browser, opener_});
    const auto opener = std::find_if(owner_->tabs.begin(), owner_->tabs.end(), [this](const auto& tab) {
      return !tab.closing && tab.browser->GetIdentifier() == opener_;
    });
    if (opener == owner_->tabs.end()) browser->GetHost()->CloseBrowser(true);
    return;
  }
  if (owner_->browser == nullptr) {
    owner_->browser = browser;
  }
  if (auto* tab = owner_->FindTab(browser)) {
    tab->url = browser->GetMainFrame() ? browser->GetMainFrame()->GetURL().ToString()
                                       : std::string("about:blank");
  }
  owner_->UpdateActiveState();
}

bool DesktopCefClient::OnBeforePopup(CefRefPtr<CefBrowser> opener,
                                     CefRefPtr<CefFrame>,
#if CEF_VERSION_MAJOR >= 130
                                     int,
#endif
                                     const CefString& target_url,
                                     const CefString&,
                                     WindowOpenDisposition target_disposition,
                                     bool,
                                     const CefPopupFeatures&,
                                     CefWindowInfo& window_info,
                                     CefRefPtr<CefClient>& client,
                                     CefBrowserSettings&,
                                     CefRefPtr<CefDictionaryValue>&,
                                     bool*) {
  if (owner_->shutting_down) return true;
  const std::string url = target_url.ToString();
  if (!owner_->config.native_popups || OpensAsTab(target_disposition == CEF_WOD_NEW_POPUP, url)) {
    ReplayPopupAsTab(opener, url);
    return true;
  }
  // Let Chromium create the context so it inherits the request context and
  // WindowProxy. Even about:blank must survive for providers that navigate it later.
  const auto bounds = window_info.bounds;
#if defined(_WIN32)
  window_info.SetAsPopup(nullptr, PopupTitle(target_url));
#else
  window_info.parent_window = 0;
  CefString(&window_info.window_name) = PopupTitle(target_url);
#endif
  window_info.windowless_rendering_enabled = false;
  window_info.bounds.width = bounds.width > 0 ? bounds.width : 520;
  window_info.bounds.height = bounds.height > 0 ? bounds.height : 680;
  client = new DesktopCefClient(owner_, opener_ != 0 ? opener_ : opener->GetIdentifier());
  return false;
}

bool DesktopCefClient::DoClose(CefRefPtr<CefBrowser> browser) {
  if (opener_ != 0) return false;
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
  app_link_asked_.erase(browser->GetIdentifier());
  if (opener_ != 0) {
    std::erase_if(owner_->popups, [&browser](const auto& popup) { return popup.browser->IsSame(browser); });
    return;
  }
  std::vector<CefRefPtr<CefBrowser>> children;
  for (const auto& popup : owner_->popups) {
    if (popup.opener == browser->GetIdentifier()) children.push_back(popup.browser);
  }
  for (const auto& child : children) child->GetHost()->CloseBrowser(true);
  for (auto& tab : owner_->tabs) {
    if (tab.browser && tab.browser->IsSame(browser)) {
      tab.chat_session->Close();
      if (tab.devtools) tab.devtools->CancelAll();
    }
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
    if (is_loading && !tab->loading) tab->load_progress = 0;
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
    // Partitioned tabs never contribute to cookie sync.
    if (!tab->partition) owner_->NotifyDefaultStoreLoad();
  }
  owner_->UpdateActiveState();
}

void DesktopCefClient::OnLoadStart(CefRefPtr<CefBrowser> browser,CefRefPtr<CefFrame> frame,
                                  TransitionType) {
  if(frame && frame->IsMain()) {
    app_link_asked_.erase(browser->GetIdentifier());
    if (auto* tab = owner_->FindTab(browser)) {
      tab->document_version = NextDocumentVersion();
      tab->inspector = {};
    }
  }
}

void DesktopCefClient::OnLoadError(CefRefPtr<CefBrowser> browser,
                                   CefRefPtr<CefFrame> frame,
                                   CefLoadHandler::ErrorCode error_code,
                                   const CefString& error_text,
                                   const CefString&) {
  if (!frame || !frame->IsMain()) return;
  // ERR_ABORTED is the load a newer navigation (or a stop) replaced. It must
  // not be charged to the navigation that replaced it.
  if (error_code == ERR_ABORTED) return;
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
  if (opener_ != 0) {
#if defined(_WIN32)
    const auto origin = CefString(PopupTitle(url)).ToWString();
    const auto handle = browser->GetHost()->GetWindowHandle();
    if (handle) SetWindowTextW(GetAncestor(handle, GA_ROOT), origin.c_str());
#endif
    return;
  }
  if (auto* tab = owner_->FindTab(browser)) {
    const std::string next = url.ToString();
    // A new document has no icon until OnFaviconURLChange fires. Keeping the old
    // one would leave the previous site's favicon on the pill; the registry
    // still holds it, keyed by that site's host. The comparison is with the
    // icon's own site: Navigate has already set `url` to the destination.
    if (FaviconRegistry::HostForUrl(next) != tab->favicon_host) {
      tab->favicon_url.clear();
      tab->favicon_png_base64.reset();
      tab->favicon_host.clear();
    }
    tab->url = next;
    if (owner_->navigation_sink) owner_->navigation_sink(tab->url, tab->title);
  }
  owner_->UpdateActiveState();
}

void DesktopCefClient::OnLoadingProgressChange(CefRefPtr<CefBrowser> browser, double progress) {
  if (auto* tab = owner_->FindTab(browser)) tab->load_progress = progress;
}

void DesktopCefClient::OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString& title) {
  if (auto* tab = owner_->FindTab(browser)) {
    tab->title = title.ToString();
    if (owner_->navigation_sink) owner_->navigation_sink(tab->url, tab->title);
  }
  owner_->UpdateActiveState();
}

bool DesktopCefClient::OnConsoleMessage(CefRefPtr<CefBrowser> browser,
                                        cef_log_severity_t level,
                                        const CefString& message,
                                        const CefString& source,
                                        int line) {
  if (message.ToString() == "__kelpie_3d_exit__") {
    if (auto* tab = owner_->FindTab(browser); tab && tab->inspector.active) {
      owner_->Exit3DInspector(*tab);
      return true;
    }
  }
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

  auto* tab = owner_->FindTab(browser);
  if (!tab) return false;
  owner_->console_sink({
      {"tabId", tab->id},
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

CefRefPtr<CefDialogHandler> DesktopCefClient::GetDialogHandler() {
  if (owner_->config.file_chooser) return this;
  return nullptr;
}

bool DesktopCefClient::OnRequestMediaAccessPermission(
    CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
    const CefString& requesting_origin, uint32_t requested_permissions,
    CefRefPtr<CefMediaAccessCallback> callback) {
  constexpr uint32_t microphone = CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE;
  if ((requested_permissions & microphone) == 0) return false;

  // Chromium has already checked the secure context and Permissions Policy.
  auto* tab = owner_->FindTab(browser);
  if (requested_permissions != microphone || requesting_origin.empty() ||
      !owner_->config.microphone_prompt || microphone_prompt_pending_ ||
      !tab || tab->closing || !owner_->browser || !owner_->browser->IsSame(browser)) {
    callback->Cancel();
    return true;
  }

  microphone_prompt_pending_ = true;
  TabLease lease{tab->id, tab->generation, tab->document_version};
  owner_->config.microphone_prompt(requesting_origin.ToString(),
      [client = CefRefPtr<DesktopCefClient>(this), owner = owner_->weak_from_this(),
       lease = std::move(lease), browser, frame, callback](bool allowed) {
        client->microphone_prompt_pending_ = false;
        const auto engine = owner.lock();
        const auto* target = engine ? engine->FindTab(lease) : nullptr;
        if (allowed && target && engine->browser && engine->browser->IsSame(browser) &&
            frame && frame->IsValid()) {
          callback->Continue(CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE);
        } else {
          callback->Cancel();
        }
      });
  return true;
}

bool DesktopCefClient::OnFileDialog(CefRefPtr<CefBrowser>,
                                    FileDialogMode mode,
                                    const CefString& title,
                                    const CefString&,
                                    const std::vector<CefString>& accept_filters,
#if CEF_VERSION_MAJOR >= 130
                                    const std::vector<CefString>&,
                                    const std::vector<CefString>&,
#endif
                                    CefRefPtr<CefFileDialogCallback> callback) {
  if (!owner_->config.file_chooser || mode == FILE_DIALOG_SAVE) return false;

  DesktopEngine::FileChooserRequest request;
  request.title = title.ToString();
  request.multiple = mode == FILE_DIALOG_OPEN_MULTIPLE;
  request.directory = mode == FILE_DIALOG_OPEN_FOLDER;
  for (const auto& filter : accept_filters) {
    request.accept_types.push_back(filter.ToString());
  }
  owner_->config.file_chooser(std::move(request), [callback](std::vector<std::string> paths) {
    if (paths.empty()) {
      callback->Cancel();
      return;
    }
    callback->Continue(std::vector<CefString>(paths.begin(), paths.end()));
  });
  return true;
}

void DesktopCefClient::GetViewRect(CefRefPtr<CefBrowser>, CefRect& rect) {
  rect = CefRect(0, 0, owner_->viewport.width, owner_->viewport.height);
}

void DesktopCefClient::OnPopupShow(CefRefPtr<CefBrowser> browser, bool show) {
  if (!show && owner_->browser && browser->IsSame(owner_->browser)) {
    std::lock_guard<std::mutex> lock(owner_->mutex); owner_->popup = {};
  }
}
void DesktopCefClient::OnPopupSize(CefRefPtr<CefBrowser> browser, const CefRect& rect) {
  if (owner_->browser && browser->IsSame(owner_->browser)) {
    std::lock_guard<std::mutex> lock(owner_->mutex); owner_->popup_rect = rect;
  }
}

void DesktopCefClient::OnPaint(CefRefPtr<CefBrowser> browser,
                               PaintElementType type,
                               const RectList&,
                               const void* buffer,
                               int width,
                               int height) {
  const auto* tab = owner_->FindTab(browser);
  if (!tab || tab->closing || !owner_->browser || !browser->IsSame(owner_->browser) ||
      buffer == nullptr || width <= 0 || height <= 0 ||
      (type == PET_VIEW && (width != owner_->viewport.width || height != owner_->viewport.height)) ||
      width > 16384 || height > 16384) {
    return;
  }
  const std::size_t size = static_cast<std::size_t>(width) * static_cast<std::size_t>(height) * 4U;
  std::lock_guard<std::mutex> lock(owner_->mutex);
  auto& frame = type == PET_VIEW ? owner_->frame : owner_->popup;
  frame = {tab->id, tab->generation, width, height,
      std::vector<std::uint8_t>(static_cast<const std::uint8_t*>(buffer),
                               static_cast<const std::uint8_t*>(buffer) + size)};
}

}  // namespace kelpie
