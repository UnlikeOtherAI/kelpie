#include "mollotov/cef_app_factory.h"

#include "include/cef_browser_process_handler.h"
#include "include/cef_command_line.h"

namespace mollotov {

namespace {

class DesktopCefApp final : public CefApp, public CefBrowserProcessHandler {
 public:
  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }

  void OnBeforeCommandLineProcessing(const CefString&,
                                     CefRefPtr<CefCommandLine> command_line) override {
    command_line->AppendSwitch("use-mock-keychain");
    command_line->AppendSwitch("no-sandbox");
    command_line->AppendSwitch("disable-gpu");
    command_line->AppendSwitch("disable-gpu-compositing");
  }

 private:
  IMPLEMENT_REFCOUNTING(DesktopCefApp);
};

}  // namespace

CefRefPtr<CefApp> CreateDesktopCefApp() {
  return new DesktopCefApp();
}

}  // namespace mollotov
