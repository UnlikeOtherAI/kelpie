#include "kelpie/desktop_engine.h"

#include <algorithm>
#include <mutex>
#include <utility>
#include <vector>

#include "include/cef_app.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_render_handler.h"
#include "kelpie/cef_app_factory.h"
#include "kelpie/desktop_bridge.h"

namespace kelpie {

class DesktopCefClient;

class DesktopEngine::Impl {
 public:
  explicit Impl(CefRenderer* renderer);

  bool Initialize(const DesktopEngine::Config& next_config);
  void Shutdown();
  void DoMessageLoopWork();
  std::string EvaluateJs(const std::string& script);

  DesktopEngine::ViewportState viewport;
  DesktopEngine::Config config;
  CefRenderer* renderer = nullptr;
  CefRefPtr<CefApp> app;
  CefRefPtr<DesktopCefClient> client;
  CefRefPtr<CefBrowser> browser;

  DesktopEngine::JsonEventSink console_sink;
  DesktopEngine::JsonEventSink network_sink;
  DesktopEngine::NavigationSink navigation_sink;

  bool initialized = false;
  bool loading = false;
  bool can_go_back = false;
  bool can_go_forward = false;
  std::string current_url = "about:blank";
  std::string current_title;
  std::vector<std::uint8_t> snapshot_bytes;
  std::mutex mutex;
};

class DesktopCefClient final : public CefClient,
                               public CefLifeSpanHandler,
                               public CefLoadHandler,
                               public CefDisplayHandler,
                               public CefRenderHandler {
 public:
  explicit DesktopCefClient(DesktopEngine::Impl* owner) : owner_(owner) {}

  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefRenderHandler> GetRenderHandler() override { return this; }

  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override;
  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override;
  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                            bool is_loading,
                            bool can_go_back,
                            bool can_go_forward) override;
  void OnLoadEnd(CefRefPtr<CefBrowser> browser,
                 CefRefPtr<CefFrame> frame,
                 int http_status_code) override;
  void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString& title) override;
  bool OnConsoleMessage(CefRefPtr<CefBrowser> browser,
                        cef_log_severity_t level,
                        const CefString& message,
                        const CefString& source,
                        int line) override;

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

DesktopEngine::Impl::Impl(CefRenderer* next_renderer) : renderer(next_renderer) {}

bool DesktopEngine::Impl::Initialize(const DesktopEngine::Config& next_config) {
  if (initialized) {
    return true;
  }

  config = next_config;
  viewport.width = std::max(1, config.viewport.width);
  viewport.height = std::max(1, config.viewport.height);
  viewport.offscreen = config.mode == DesktopEngine::Mode::kOffscreen;

  app = CreateDesktopCefApp();
  client = new DesktopCefClient(this);

  CefMainArgs main_args(config.argc, config.argv);
  CefSettings settings;
  settings.no_sandbox = true;
  settings.windowless_rendering_enabled = config.mode == DesktopEngine::Mode::kOffscreen ? 1 : 0;
  settings.external_message_pump = config.external_message_pump ? 1 : 0;
  if (!config.cache_path.empty()) {
    CefString(&settings.cache_path) = config.cache_path;
  }
  if (!config.user_agent.empty()) {
    CefString(&settings.user_agent) = config.user_agent;
  }
  if (!config.browser_subprocess_path.empty()) {
    CefString(&settings.browser_subprocess_path) = config.browser_subprocess_path;
  }
  if (!config.resources_dir_path.empty()) {
    CefString(&settings.resources_dir_path) = config.resources_dir_path;
  }
  if (!config.locales_dir_path.empty()) {
    CefString(&settings.locales_dir_path) = config.locales_dir_path;
  }

  initialized = CefInitialize(main_args, settings, app.get(), nullptr);
  if (!initialized) {
    return false;
  }

  CefWindowInfo window_info;
  if (config.mode == DesktopEngine::Mode::kOffscreen) {
    window_info.SetAsWindowless(0);
  } else if (config.configure_window_info) {
    config.configure_window_info(static_cast<void*>(&window_info));
  } else {
    return false;
  }

  CefBrowserSettings browser_settings;
  browser = CefBrowserHost::CreateBrowserSync(
      window_info,
      client.get(),
      config.initial_url.empty() ? "about:blank" : config.initial_url,
      browser_settings,
      nullptr,
      nullptr);

  renderer->SetCallbacks({
      [this](const std::string& script) { return EvaluateJs(script); },
      [this]() { return snapshot_bytes; },
      [this](const std::string& url) {
        if (browser && browser->GetMainFrame()) {
          browser->GetMainFrame()->LoadURL(url);
          current_url = url;
        }
      },
      [this]() { return current_url; },
      [this]() { return current_title; },
      [this]() { return loading; },
      [this]() { return can_go_back; },
      [this]() { return can_go_forward; },
      [this]() {
        if (browser) {
          browser->GoBack();
        }
      },
      [this]() {
        if (browser) {
          browser->GoForward();
        }
      },
      [this]() {
        if (browser) {
          browser->Reload();
        }
      },
  });

  return browser != nullptr;
}

void DesktopEngine::Impl::Shutdown() {
  if (!initialized) {
    return;
  }
  if (browser && browser->GetHost()) {
    browser->GetHost()->CloseBrowser(true);
  }
  browser = nullptr;
  client = nullptr;
  app = nullptr;
  CefShutdown();
  initialized = false;
}

void DesktopEngine::Impl::DoMessageLoopWork() {
  if (initialized && config.external_message_pump) {
    CefDoMessageLoopWork();
  }
}

std::string DesktopEngine::Impl::EvaluateJs(const std::string& script) {
  if (!browser || !browser->GetMainFrame()) {
    return std::string();
  }
  CefRefPtr<CefFrame> frame = browser->GetMainFrame();
  frame->ExecuteJavaScript(script, frame->GetURL(), 0);
  return std::string();
}

void DesktopCefClient::OnAfterCreated(CefRefPtr<CefBrowser> browser) {
  owner_->browser = browser;
  owner_->current_url = browser->GetMainFrame() ? browser->GetMainFrame()->GetURL().ToString()
                                                : std::string("about:blank");
}

void DesktopCefClient::OnBeforeClose(CefRefPtr<CefBrowser> browser) {
  if (owner_->browser && owner_->browser->IsSame(browser)) {
    owner_->browser = nullptr;
  }
}

void DesktopCefClient::OnLoadingStateChange(CefRefPtr<CefBrowser>,
                                            bool is_loading,
                                            bool can_go_back,
                                            bool can_go_forward) {
  owner_->loading = is_loading;
  owner_->can_go_back = can_go_back;
  owner_->can_go_forward = can_go_forward;
}

void DesktopCefClient::OnLoadEnd(CefRefPtr<CefBrowser> browser,
                                 CefRefPtr<CefFrame> frame,
                                 int) {
  if (!frame || !frame->IsMain()) {
    return;
  }
  owner_->current_url = frame->GetURL().ToString();
  frame->ExecuteJavaScript(CombinedBridgeScript(), frame->GetURL(), 0);
  if (owner_->navigation_sink) {
    owner_->navigation_sink(owner_->current_url, owner_->current_title);
  }
}

void DesktopCefClient::OnTitleChange(CefRefPtr<CefBrowser>, const CefString& title) {
  owner_->current_title = title.ToString();
  if (owner_->navigation_sink) {
    owner_->navigation_sink(owner_->current_url, owner_->current_title);
  }
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

DesktopEngine::DesktopEngine()
    : renderer_(std::make_unique<CefRenderer>()),
      impl_(std::make_unique<Impl>(renderer_.get())) {}

DesktopEngine::~DesktopEngine() = default;

bool DesktopEngine::Initialize(const Config& config) {
  return impl_->Initialize(config);
}

void DesktopEngine::Shutdown() {
  impl_->Shutdown();
}

void DesktopEngine::DoMessageLoopWork() {
  impl_->DoMessageLoopWork();
}

bool DesktopEngine::is_initialized() const {
  return impl_->initialized;
}

bool DesktopEngine::is_offscreen() const {
  return impl_->viewport.offscreen;
}

DesktopEngine::ViewportState DesktopEngine::viewport() const {
  return impl_->viewport;
}

bool DesktopEngine::ResizeViewport(int width, int height) {
  impl_->viewport.width = std::max(1, width);
  impl_->viewport.height = std::max(1, height);
  if (impl_->browser && impl_->browser->GetHost()) {
    impl_->browser->GetHost()->WasResized();
  }
  return true;
}

bool DesktopEngine::SendFocusEvent(bool focused) {
  if (!impl_->browser || !impl_->browser->GetHost()) {
    return false;
  }
  impl_->browser->GetHost()->SetFocus(focused);
  return true;
}

bool DesktopEngine::SendMouseMoveEvent(int x, int y, bool mouse_leave) {
  if (!impl_->browser || !impl_->browser->GetHost()) {
    return false;
  }
  CefMouseEvent event;
  event.x = x;
  event.y = y;
  impl_->browser->GetHost()->SendMouseMoveEvent(event, mouse_leave);
  return true;
}

bool DesktopEngine::SendMouseClickEvent(int x, int y, int button, bool mouse_up, int click_count) {
  if (!impl_->browser || !impl_->browser->GetHost()) {
    return false;
  }
  cef_mouse_button_type_t button_type = MBT_LEFT;
  if (button == 2) {
    button_type = MBT_MIDDLE;
  } else if (button == 3) {
    button_type = MBT_RIGHT;
  }

  CefMouseEvent event;
  event.x = x;
  event.y = y;
  impl_->browser->GetHost()->SendMouseClickEvent(event, button_type, mouse_up, click_count);
  return true;
}

bool DesktopEngine::SendMouseWheelEvent(int x, int y, int delta_x, int delta_y) {
  if (!impl_->browser || !impl_->browser->GetHost()) {
    return false;
  }
  CefMouseEvent event;
  event.x = x;
  event.y = y;
  impl_->browser->GetHost()->SendMouseWheelEvent(event, delta_x, delta_y);
  return true;
}

void DesktopEngine::SetConsoleSink(JsonEventSink sink) {
  impl_->console_sink = std::move(sink);
}

void DesktopEngine::SetNetworkSink(JsonEventSink sink) {
  impl_->network_sink = std::move(sink);
}

void DesktopEngine::SetNavigationSink(NavigationSink sink) {
  impl_->navigation_sink = std::move(sink);
}

CefRenderer& DesktopEngine::renderer() {
  return *renderer_;
}

const CefRenderer& DesktopEngine::renderer() const {
  return *renderer_;
}

}  // namespace kelpie
