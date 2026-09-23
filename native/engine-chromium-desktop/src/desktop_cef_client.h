#pragma once

#include <vector>

#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_jsdialog_handler.h"
#include "include/cef_render_handler.h"
#include "include/cef_version.h"

#include "desktop_engine_impl.h"

namespace kelpie {

// The single CefClient behind every Kelpie tab.
//
// Its event methods are split across translation units by responsibility:
// lifecycle, loading, and dialogs in `desktop_engine.cpp`; favicon capture in
// `desktop_engine_favicon.cpp`. The declaration lives here so both can define
// members of the same class.
class DesktopCefClient final : public CefClient,
                               public CefLifeSpanHandler,
                               public CefLoadHandler,
                               public CefDisplayHandler,
                               public CefRenderHandler,
                               public CefJSDialogHandler {
 public:
  explicit DesktopCefClient(DesktopEngine::Impl* owner) : owner_(owner) {}

  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefRenderHandler> GetRenderHandler() override { return this; }
  CefRefPtr<CefJSDialogHandler> GetJSDialogHandler() override { return this; }

  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override;
  bool OnBeforePopup(CefRefPtr<CefBrowser> browser,
                     CefRefPtr<CefFrame> frame,
#if CEF_VERSION_MAJOR >= 130
                     int popup_id,
#endif
                     const CefString& target_url,
                     const CefString& target_frame_name,
                     WindowOpenDisposition target_disposition,
                     bool user_gesture,
                     const CefPopupFeatures& popup_features,
                     CefWindowInfo& window_info,
                     CefRefPtr<CefClient>& client,
                     CefBrowserSettings& settings,
                     CefRefPtr<CefDictionaryValue>& extra_info,
                     bool* no_javascript_access) override;
  bool DoClose(CefRefPtr<CefBrowser> browser) override;
  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override;
  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                            bool is_loading,
                            bool can_go_back,
                            bool can_go_forward) override;
  void OnLoadStart(CefRefPtr<CefBrowser> browser,
                   CefRefPtr<CefFrame> frame,
                   TransitionType transition_type) override;
  void OnLoadEnd(CefRefPtr<CefBrowser> browser,
                 CefRefPtr<CefFrame> frame,
                 int http_status_code) override;
  void OnLoadError(CefRefPtr<CefBrowser> browser,
                   CefRefPtr<CefFrame> frame,
                   CefLoadHandler::ErrorCode error_code,
                   const CefString& error_text,
                   const CefString& failed_url) override;
  void OnAddressChange(CefRefPtr<CefBrowser> browser,
                       CefRefPtr<CefFrame> frame,
                       const CefString& url) override;
  void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString& title) override;
  void OnFaviconURLChange(CefRefPtr<CefBrowser> browser,
                          const std::vector<CefString>& icon_urls) override;
  bool OnConsoleMessage(CefRefPtr<CefBrowser> browser,
                        cef_log_severity_t level,
                        const CefString& message,
                        const CefString& source,
                        int line) override;
  bool OnJSDialog(CefRefPtr<CefBrowser> browser,
                  const CefString& origin_url,
                  cef_jsdialog_type_t dialog_type,
                  const CefString& message_text,
                  const CefString& default_prompt_text,
                  CefRefPtr<CefJSDialogCallback> callback,
                  bool& suppress_message) override;
  void OnResetDialogState(CefRefPtr<CefBrowser> browser) override;

  void GetViewRect(CefRefPtr<CefBrowser> browser, CefRect& rect) override;
  void OnPaint(CefRefPtr<CefBrowser> browser,
               PaintElementType type,
               const RectList& dirty_rects,
               const void* buffer,
               int width,
               int height) override;

 private:
  DesktopEngine::Impl* owner_;

  IMPLEMENT_REFCOUNTING(DesktopCefClient);
};

}  // namespace kelpie
