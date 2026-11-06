#include "kelpie/cef_app_factory.h"
#if defined(KELPIE_LINUX_STARTUP_TEST_TRACE) && KELPIE_LINUX_STARTUP_TEST_TRACE
#include "startup_test_trace.h"
#else
#define KELPIE_STARTUP_AUX(event) ((void)0)
#endif


#include "include/cef_browser_process_handler.h"
#include "include/cef_command_line.h"

#include <mutex>

#include "start_page_scheme.h"

namespace kelpie {

namespace {

std::mutex scheduler_mutex;
std::function<void(std::int64_t)> message_pump_scheduler;

class DesktopCefApp final : public CefApp, public CefBrowserProcessHandler {
 public:
  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }

  // Runs on the main thread of every process. The renderer must agree with the
  // browser about `kelpie://` or the start page loses its origin and cannot
  // fetch its own payload.
  void OnRegisterCustomSchemes(CefRawPtr<CefSchemeRegistrar> registrar) override {
    RegisterKelpieCustomSchemes(registrar);
  }

  void OnBeforeCommandLineProcessing(const CefString&,
                                     CefRefPtr<CefCommandLine> command_line) override {
    command_line->AppendSwitch("use-mock-keychain");
    command_line->AppendSwitch("disable-gpu");
    command_line->AppendSwitch("disable-gpu-compositing");
#if defined(__linux__)
    // Offscreen rendering still initializes Ozone. Linux defaults to X11,
    // which requires a display even when no native window is created.
    if (command_line->HasSwitch("headless")) {
      command_line->AppendSwitchWithValue("ozone-platform", "headless");
    }
#endif
  }

#if defined(KELPIE_LINUX_STARTUP_TEST_TRACE) && KELPIE_LINUX_STARTUP_TEST_TRACE
  void OnContextInitialized() override { KELPIE_STARTUP_AUX(CONTEXT_INITIALIZED); }
#endif

  void OnScheduleMessagePumpWork(int64_t delay_ms) override {
    KELPIE_STARTUP_AUX(SCHEDULE_FIRST);
    std::lock_guard<std::mutex> lock(scheduler_mutex);
    if (message_pump_scheduler) message_pump_scheduler(delay_ms);
  }

 private:
  IMPLEMENT_REFCOUNTING(DesktopCefApp);
};

}  // namespace

CefRefPtr<CefApp> CreateDesktopCefApp() {
  static CefRefPtr<CefApp> app = new DesktopCefApp();
  return app;
}

void SetDesktopCefMessagePumpScheduler(std::function<void(std::int64_t)> scheduler) {
  std::lock_guard<std::mutex> lock(scheduler_mutex);
  message_pump_scheduler = std::move(scheduler);
}

}  // namespace kelpie
