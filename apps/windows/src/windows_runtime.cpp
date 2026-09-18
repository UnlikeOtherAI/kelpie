#include "windows_app.h"

#include "cef_pump_deadline.h"
#include "kelpie/desktop_http_server.h"
#include "kelpie/cef_app_factory.h"
#include "windows_utf.h"

#include <algorithm>
#include <memory>
#include <optional>

#if defined(HAS_CEF)
#include "include/cef_app.h"
#endif

namespace kelpie::windows {
namespace {

constexpr UINT_PTR kCefPumpTimerId = 0x4B50;
constexpr UINT kScheduleCefPumpMessage = WM_APP + 0x4B50;
HWND g_cef_pump_window = nullptr;
CefPumpDeadline g_cef_deadline;

std::int64_t PumpNow() {
  return static_cast<std::int64_t>(GetTickCount64());
}

void CALLBACK PumpCefTimer(HWND hwnd, UINT, UINT_PTR timer_id, DWORD) {
#if defined(HAS_CEF)
  if (g_cef_deadline.ConsumeIfDue(PumpNow())) {
    KillTimer(hwnd, timer_id);
    CefDoMessageLoopWork();
  } else if (const auto due = g_cef_deadline.due_ms()) {
    SetTimer(hwnd, timer_id, static_cast<UINT>(std::max<std::int64_t>(1, *due - PumpNow())),
             &PumpCefTimer);
  } else {
    KillTimer(hwnd, timer_id);
  }
#endif
}

LRESULT CALLBACK CefPumpWindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == kScheduleCefPumpMessage) {
    const auto now = PumpNow();
    if (g_cef_deadline.Schedule(now, static_cast<std::int64_t>(wparam))) {
      const auto due = *g_cef_deadline.due_ms();
      if (due <= now) {
        PostMessageW(hwnd, kScheduleCefPumpMessage + 1, 0, 0);
      } else {
        SetTimer(hwnd, kCefPumpTimerId, static_cast<UINT>(due - now), &PumpCefTimer);
      }
    }
    return 0;
  }
  if (message == kScheduleCefPumpMessage + 1) {
    if (g_cef_deadline.ConsumeIfDue(PumpNow())) {
      KillTimer(hwnd, kCefPumpTimerId);
#if defined(HAS_CEF)
      CefDoMessageLoopWork();
#endif
    }
    return 0;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

bool CreateCefPumpWindow(HINSTANCE instance) {
  if (g_cef_pump_window != nullptr) return true;
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = CefPumpWindowProc;
  window_class.hInstance = instance;
  window_class.lpszClassName = L"KelpieCefPumpWindow";
  RegisterClassW(&window_class);
  g_cef_pump_window = CreateWindowExW(0, window_class.lpszClassName, L"", 0, 0, 0, 0, 0,
                                      HWND_MESSAGE, nullptr, instance, nullptr);
  return g_cef_pump_window != nullptr;
}

bool HasAttachedActiveTab(DesktopApp* app, const Win32BrowserView* browser_view) {
  return app != nullptr && browser_view != nullptr &&
      app->engine().IsActiveNativeBrowserAttached(browser_view->hwnd(), std::chrono::seconds(2));
}

#if defined(HAS_CEF)
void ConfigureAlloyChildWindow(CefWindowInfo* info, HWND parent) {
  if (info == nullptr || parent == nullptr || !IsWindow(parent)) return;
  RECT bounds{};
  if (!GetClientRect(parent, &bounds)) return;
  info->SetAsChild(parent, CefRect(0, 0, std::max(1L, bounds.right - bounds.left),
                                   std::max(1L, bounds.bottom - bounds.top)));
  // CEF152's SetAsChild retains the Chrome default. Kelpie owns all browser
  // chrome, so every child tab must use renderer-only Alloy.
  info->runtime_style = CEF_RUNTIME_STYLE_ALLOY;
}
#endif

}  // namespace

bool WindowsApp::InitializeDesktopRuntime() {
  startup_diagnostics_.Enter(StartupStage::kNativeHost);
  if (!native_control_.Create(instance_, browser_view_->hwnd(), config_.width, config_.height)) {
    startup_diagnostics_.Fail(StartupStage::kNativeHost, "Native browser host could not be created");
    return false;
  }
  if (!CreateCefPumpWindow(instance_)) {
    startup_diagnostics_.Fail(StartupStage::kNativeHost, "Chromium message pump could not be created");
    native_control_.Shutdown();
    return false;
  }
#if defined(HAS_CEF)
  // cef_app_factory.cpp only compiles with the Chromium desktop engine, so
  // the no-CEF configuration has no symbol to call here.
  SetDesktopCefMessagePumpScheduler([](std::int64_t delay_ms) {
    if (g_cef_pump_window != nullptr) {
      PostMessageW(g_cef_pump_window, kScheduleCefPumpMessage, static_cast<WPARAM>(delay_ms), 0);
    }
  });
#endif

  desktop_app_ = std::make_unique<DesktopApp>();
  // Navigation callbacks may persist history immediately, so restore stores
  // before Chromium begins loading any page.
  LoadStores();

  DesktopApp::Config runtime;
  runtime.platform = Platform::kWindows;
  runtime.engine_name = "chromium";
  runtime.port = config_.port;
  runtime.app_name = "kelpie";
  runtime.app_version = "0.1.1";
  runtime.start_stdio_mcp = config_.mcp_stdio;
  runtime.bind_host = "127.0.0.1";
  runtime.control_token = profile_session_.token();
  device_info_provider_.Configure(config_.port, config_.width, config_.height, runtime.app_version);
  runtime.device_info_provider = &device_info_provider_;
  runtime.device_id = device_info_provider_
                          .Collect(config_.port, config_.width, config_.height, runtime.app_version)
                          .id;
  {
    std::lock_guard<std::mutex> lock(shell_state_mutex_);
    home_url_ = config_.initial_url;
  }
  runtime.set_home = [this](std::string url) {
    std::lock_guard<std::mutex> lock(shell_state_mutex_);
    home_url_ = std::move(url);
    config_.initial_url = home_url_;
    SaveSettings();
    return BrowserControlResult::Success();
  };
  runtime.get_home = [this](std::string* url) {
    if (url == nullptr) return BrowserControlResult::Failure("INTERNAL", "home URL is required");
    std::lock_guard<std::mutex> lock(shell_state_mutex_);
    *url = home_url_;
    return BrowserControlResult::Success();
  };
  runtime.show_native_toast = [this](std::string message) {
    const bool shown = native_control_.Invoke(
        [this, message = std::move(message)] {
          shell_->ShowToast(utf::Utf8ToWideDisplay(message));
          return true;
        },
        std::chrono::seconds(2));
    return shown ? BrowserControlResult::Success()
                 : BrowserControlResult::Failure("WEBVIEW_ERROR", "Native control did not show the toast");
  };
  runtime.set_native_fullscreen = [this](bool enabled) {
    const bool complete = native_control_.Invoke(
        [this, enabled] { return native_control_.SetFullscreen(enabled); }, std::chrono::seconds(2));
    return complete ? BrowserControlResult::Success()
                    : BrowserControlResult::Failure("WEBVIEW_ERROR", "Native fullscreen operation failed");
  };
  runtime.get_native_fullscreen = [this](bool* enabled) {
    if (enabled == nullptr) return BrowserControlResult::Failure("INTERNAL", "fullscreen result is required");
    auto result = std::make_shared<bool>(false);
    const bool complete = native_control_.Invoke(
        [this, result] {
          *result = native_control_.fullscreen();
          return true;
        },
        std::chrono::seconds(2));
    if (!complete) return BrowserControlResult::Failure("WEBVIEW_ERROR", "Native fullscreen query failed");
    *enabled = *result;
    return BrowserControlResult::Success();
  };
  runtime.viewport_supplier = [this]() {
    auto result = std::make_shared<std::optional<RECT>>();
    if (!native_control_.Invoke(
            [this, result] {
              *result = native_control_.viewport();
              return result->has_value();
            },
            std::chrono::seconds(2)) ||
        !*result) {
      return nlohmann::json();
    }
    return nlohmann::json{{"width", (*result)->right - (*result)->left},
                          {"height", (*result)->bottom - (*result)->top},
                          {"devicePixelRatio", 1.0}, {"platform", "windows"}};
  };
  runtime.resize_viewport = [this](int width, int height) {
    return native_control_.Invoke(
        [this, width, height] { return native_control_.Resize(width, height); }, std::chrono::seconds(2));
  };
  runtime.reset_viewport = [this]() {
    return native_control_.Invoke([this] { return native_control_.ResetViewport(); },
                                  std::chrono::seconds(2));
  };
  runtime.request_shutdown = [this]() {
    if (shell_ == nullptr || shell_->hwnd() == nullptr) {
      return BrowserControlResult::Failure("INTERNAL", "Native window is unavailable");
    }
    if (!PostMessageW(shell_->hwnd(), WM_CLOSE, 0, 0)) {
      return BrowserControlResult::Failure("INTERNAL", "Unable to request native window close");
    }
    return BrowserControlResult::Success();
  };
  runtime.engine.mode = DesktopEngine::Mode::kWindowed;
  runtime.engine.process_instance = config_.cef_process_instance;
  runtime.engine.sandbox_info = config_.sandbox_info;
  runtime.engine.initial_url = config_.initial_url;
  if (!config_.url_overridden && !session_snapshot_.tabs.empty()) {
    runtime.engine.restored_next_tab_id = session_snapshot_.next_tab_id;
    for (const auto& tab : session_snapshot_.tabs) {
      runtime.engine.restored_tabs.push_back({tab.id, tab.url, tab.active});
    }
  }
  runtime.engine.cache_path = utf::WideToUtf8((config_.profile_dir / "cache").wstring()).value_or(std::string());
  runtime.engine.configure_window_info = [this](void* raw_info) {
#if defined(HAS_CEF)
    ConfigureAlloyChildWindow(static_cast<CefWindowInfo*>(raw_info), browser_view_->hwnd());
#else
    (void)raw_info;
#endif
  };
  runtime.engine.configure_tab_window_info = [this](void* raw_info, const std::string&) {
#if defined(HAS_CEF)
    ConfigureAlloyChildWindow(static_cast<CefWindowInfo*>(raw_info), browser_view_->hwnd());
#else
    (void)raw_info;
#endif
  };
  startup_diagnostics_.Enter(StartupStage::kCefBrowser);
  if (!desktop_app_->Start(runtime)) {
    startup_diagnostics_.Fail(StartupStage::kCefBrowser, desktop_app_->last_error());
    if (!desktop_app_->is_running()) {
      desktop_app_.reset();
    } else {
      ShutdownDesktopRuntime();
    }
    return false;
  }
  startup_diagnostics_.Enter(StartupStage::kAttachedBrowser);
  if (!HasAttachedActiveTab(desktop_app_.get(), browser_view_.get())) {
    startup_diagnostics_.Fail(StartupStage::kAttachedBrowser, "Chromium did not attach a usable browser child");
    ShutdownDesktopRuntime();
    return false;
  }
  startup_diagnostics_.Enter(StartupStage::kHttpListener);
  const int bound_port = desktop_app_->http_server().bound_port();
  if (bound_port <= 0) {
    startup_diagnostics_.Fail(StartupStage::kHttpListener, "The loopback listener did not bind");
    ShutdownDesktopRuntime();
    return false;
  }
  // Public discovery must report the socket that actually bound, never only
  // the requested configuration value.
  device_info_provider_.Configure(bound_port, config_.width, config_.height, runtime.app_version);
  startup_diagnostics_.Enter(StartupStage::kReadinessPublication);
  std::string readiness_error;
  if (!profile_session_.PublishReadiness(runtime.device_id, bound_port,
                                         runtime.start_stdio_mcp, &readiness_error)) {
    startup_diagnostics_.Fail(StartupStage::kReadinessPublication, readiness_error);
    ShutdownDesktopRuntime();
    return false;
  }
  browser_view_->ShowFallback(false);
  startup_diagnostics_.Ready();
  return true;
}

bool WindowsApp::ShutdownDesktopRuntime() {
  // CEF must deliver every OnBeforeClose before CefShutdown. Keep the owner
  // and message pump alive if shutdown is still draining browser callbacks.
  if (desktop_app_) {
    if (!desktop_app_->Stop()) return false;
    desktop_app_.reset();
  }
  native_control_.Shutdown();
#if defined(HAS_CEF)
  SetDesktopCefMessagePumpScheduler({});
#endif
  if (g_cef_pump_window != nullptr) {
    KillTimer(g_cef_pump_window, kCefPumpTimerId);
    DestroyWindow(g_cef_pump_window);
    g_cef_pump_window = nullptr;
  }
  profile_session_.ClearReadiness();
  return true;
}

void WindowsApp::UpdateBrowserStateFromRuntime() {
  if (!desktop_app_) return;
  std::vector<TabSnapshot> tabs;
  if (!desktop_app_->engine().GetTabs(&tabs, std::chrono::milliseconds(20)).ok) return;
  for (const auto& tab : tabs) {
    if (tab.active) {
      OnBrowserStateChanged({tab.url, tab.title, tab.is_loading, tab.can_go_back, tab.can_go_forward});
      SaveSession();
      return;
    }
  }
}

}  // namespace kelpie::windows