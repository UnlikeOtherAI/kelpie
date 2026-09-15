#include "kelpie/desktop_engine.h"

#include <algorithm>
#include <chrono>
#include <mutex>
#include <thread>
#include <utility>
#include <vector>

#if defined(_WIN32)
#include <windows.h>
#endif

#include "include/cef_app.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_render_handler.h"
#include "include/cef_jsdialog_handler.h"
#include "kelpie/cef_app_factory.h"
#include "kelpie/desktop_bridge.h"
#include "desktop_engine_impl.h"

namespace kelpie {



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
                     int popup_id,
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

#if defined(_WIN32)
  CefMainArgs main_args(static_cast<HINSTANCE>(config.process_instance));
#else
  CefMainArgs main_args(config.argc, config.argv);
#endif
  CefSettings settings;
#if defined(_WIN32)
  if (config.sandbox_info == nullptr) return false;
#endif
  settings.no_sandbox = false;
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

  initialized = CefInitialize(main_args, settings, app.get(), config.sandbox_info);
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
  if (browser) {
    Tab initial;
    initial.id = "tab-1";
    initial.browser = browser;
    initial.devtools = new DesktopDevToolsSession();
    initial.url = config.initial_url.empty() ? "about:blank" : config.initial_url;
    tabs.push_back(std::move(initial));
  }

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
  for (auto& tab : tabs) {
    if (tab.devtools) tab.devtools->CancelAll();
    if (tab.browser && tab.browser->GetHost()) tab.browser->GetHost()->CloseBrowser(true);
  }
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
  while (!tabs.empty() && std::chrono::steady_clock::now() < deadline) {
    CefDoMessageLoopWork();
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  if (!tabs.empty()) {
    // CEF requires every browser close callback before CefShutdown. Keep the
    // runtime alive rather than invalidating outstanding CEF references.
    return;
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
                                     int,
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

void DesktopCefClient::OnBeforeClose(CefRefPtr<CefBrowser> browser) {
  for (auto& tab : owner_->tabs) {
    if (tab.browser && tab.browser->IsSame(browser) && tab.devtools) tab.devtools->CancelAll();
  }
  owner_->tabs.erase(std::remove_if(owner_->tabs.begin(), owner_->tabs.end(),
      [&browser](const DesktopEngine::Impl::Tab& tab) { return tab.browser->IsSame(browser); }),
      owner_->tabs.end());
  if (owner_->browser && owner_->browser->IsSame(browser)) {
    owner_->browser = owner_->tabs.empty() ? nullptr : owner_->tabs.front().browser;
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
  }
  owner_->UpdateActiveState();
  if (owner_->navigation_sink && owner_->browser && owner_->browser->IsSame(browser)) {
    owner_->navigation_sink(owner_->current_url, owner_->current_title);
  }
}

void DesktopCefClient::OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString& title) {
  if (auto* tab = owner_->FindTab(browser)) {
    tab->title = title.ToString();
  }
  owner_->UpdateActiveState();
  if (owner_->navigation_sink && owner_->browser && owner_->browser->IsSame(browser)) {
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
