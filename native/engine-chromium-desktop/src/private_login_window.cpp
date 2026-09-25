#include "kelpie/private_login_window.h"
#include "include/cef_client.h"
#include "include/cef_parser.h"
#include "include/cef_request_context_handler.h"
#include "include/cef_version.h"
#include "include/views/cef_browser_view.h"
#include "include/views/cef_browser_view_delegate.h"
#include "include/views/cef_fill_layout.h"
#include "include/views/cef_window.h"
#include "include/views/cef_window_delegate.h"

namespace kelpie {
namespace {
class LoginWindow;
CefRefPtr<LoginWindow> current;

class LoginWindow final : public CefClient,
                          public CefLifeSpanHandler,
                          public CefDisplayHandler,
                          public CefContextMenuHandler,
                          public CefKeyboardHandler,
                          public CefWindowDelegate,
                          public CefBrowserViewDelegate {
 public:
  explicit LoginWindow(std::function<void()> cancelled) : cancelled_(std::move(cancelled)) {}
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefContextMenuHandler> GetContextMenuHandler() override { return this; }
  CefRefPtr<CefKeyboardHandler> GetKeyboardHandler() override { return this; }
  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override { browser_=browser; }
  void OnBeforeClose(CefRefPtr<CefBrowser>) override { browser_=nullptr; }
  void OnAddressChange(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, const CefString& url) override {
    if (!frame->IsMain() || !window_) return;
    CefURLParts parts;
    if (CefParseURL(url,parts)) {
      // Show the real origin without exposing OAuth state or callback codes.
      window_->SetTitle("Login/register — "+CefString(&parts.scheme).ToString()+"://"+CefString(&parts.host).ToString());
    }
  }
  void OnBeforeContextMenu(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>,
                          CefRefPtr<CefContextMenuParams>, CefRefPtr<CefMenuModel> menu) override { menu->Clear(); }
  bool OnPreKeyEvent(CefRefPtr<CefBrowser>, const CefKeyEvent& event, CefEventHandle, bool*) override {
    return event.windows_key_code==123 || // F12
        ((event.modifiers&EVENTFLAG_CONTROL_DOWN) && (event.modifiers&EVENTFLAG_SHIFT_DOWN) &&
         (event.windows_key_code=='I' || event.windows_key_code=='J' || event.windows_key_code=='C'));
  }
  bool OnBeforePopup(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame>,
#if CEF_VERSION_MAJOR >= 130
                     int,
#endif
                     const CefString& url, const CefString&, WindowOpenDisposition, bool,
                     const CefPopupFeatures&, CefWindowInfo&, CefRefPtr<CefClient>&,
                     CefBrowserSettings&, CefRefPtr<CefDictionaryValue>&, bool*) override {
    // Keep provider handoffs inside the same private surface and context.
    browser->GetMainFrame()->LoadURL(url);
    return true;
  }
  void OnWindowCreated(CefRefPtr<CefWindow> window) override {
    window_=window;
    window->SetTitle("Login/register");
    window->SetToFillLayout();
    window->AddChildView(view_);
    window->CenterWindow(CefSize(520,720));
    window->Show();
    view_->RequestFocus();
  }
  bool CanClose(CefRefPtr<CefWindow>) override {
    return !browser_ || browser_->GetHost()->TryCloseBrowser();
  }
  void OnWindowDestroyed(CefRefPtr<CefWindow>) override {
    window_=nullptr; view_=nullptr;
    auto cancelled=std::move(cancelled_);
    current=nullptr;
    if (cancelled) cancelled();
  }
#if CEF_VERSION_MAJOR >= 130
  cef_runtime_style_t GetWindowRuntimeStyle() override { return CEF_RUNTIME_STYLE_ALLOY; }
  cef_runtime_style_t GetBrowserRuntimeStyle() override { return CEF_RUNTIME_STYLE_ALLOY; }
#endif
  bool Open(const std::string& url) {
    CefRequestContextSettings context_settings; // Empty cache path: memory-only cookies.
    auto context=CefRequestContext::CreateContext(context_settings,nullptr);
    CefBrowserSettings settings;
    view_=CefBrowserView::CreateBrowserView(this,url,settings,nullptr,context,this);
    if (!view_) return false;
    return CefWindow::CreateTopLevelWindow(this)!=nullptr;
  }
  void Close() {
    cancelled_={};
    if (browser_) browser_->GetHost()->CloseBrowser(true);
    else if (window_) window_->Close();
  }
 private:
  CefRefPtr<CefBrowser> browser_;
  CefRefPtr<CefBrowserView> view_;
  CefRefPtr<CefWindow> window_;
  std::function<void()> cancelled_;
  IMPLEMENT_REFCOUNTING(LoginWindow);
};
}
bool OpenPrivateLoginWindow(const std::string& url,std::function<void()> cancelled) {
  if (current) return false;
  current=new LoginWindow(std::move(cancelled));
  if (current->Open(url)) return true;
  current=nullptr;
  return false;
}
bool ClosePrivateLoginWindow() {
  if (current) current->Close();
  return !current;
}
}
