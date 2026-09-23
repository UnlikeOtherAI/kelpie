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
#include "include/cef_version.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_render_handler.h"
#include "include/cef_jsdialog_handler.h"
#include "include/cef_task.h"
#include "kelpie/cef_app_factory.h"
#include "kelpie/desktop_bridge.h"
#include "kelpie/internal_scheme.h"
#include "desktop_cef_client.h"
#include "desktop_engine_impl.h"
#include "start_page_scheme.h"

namespace kelpie {

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


DesktopEngine::Impl::Impl(CefRenderer* next_renderer) : renderer(next_renderer) {}

bool DesktopEngine::Impl::WaitForPartition(DesktopPartitionRegistry::Entry* entry) {
  if (entry == nullptr) return false;
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
  while (!entry->ready() && std::chrono::steady_clock::now() < deadline) {
    CefDoMessageLoopWork();
    std::this_thread::sleep_for(std::chrono::milliseconds(5));
  }
  return entry->ready();
}

bool DesktopEngine::Impl::Initialize(const DesktopEngine::Config& next_config) {
  if (initialized) {
    return true;
  }

  config = next_config;
  last_error.clear();
  shutting_down = false;
  partitions.SetRoot(config.partitions_path);
  // A previous run may have failed to unlink a partition directory and parked
  // it in .trash instead. Nothing holds those files now, so clear them before
  // Chromium opens anything under the same root.
  DesktopPartitionRegistry::PurgeTrash(config.partitions_path);
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
  if (config.sandbox_info == nullptr) {
    last_error = "The sandbox bootstrap is unavailable";
    return false;
  }
  settings.no_sandbox = false;
#else
  // Linux's pinned CEF120 packaging does not ship the sandbox helper. Keep its
  // existing configuration explicit until that artifact is upgraded.
  settings.no_sandbox = true;
#endif
  settings.windowless_rendering_enabled = config.mode == DesktopEngine::Mode::kOffscreen ? 1 : 0;
  settings.external_message_pump = config.external_message_pump ? 1 : 0;
  if (!config.root_cache_path.empty()) {
    CefString(&settings.root_cache_path) = config.root_cache_path;
  }
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
    last_error = "Chromium framework initialization failed";
    return false;
  }

  // `kelpie://start` is first-party content served by this process, not a script
  // injected into a page. The supplier reads the application's own stores.
  if (!RegisterStartPageSchemeHandler(config.start_page_data_supplier)) {
    last_error = "Chromium rejected the kelpie:// scheme handler";
    CefShutdown();
    initialized = false;
    return false;
  }

  CefWindowInfo window_info;
  if (config.mode == DesktopEngine::Mode::kOffscreen) {
    window_info.SetAsWindowless(0);
  } else if (config.configure_window_info) {
    config.configure_window_info(static_cast<void*>(&window_info));
  } else {
    last_error = "No native browser host is configured";
    app = nullptr;
    client = nullptr;
    CefShutdown();
    initialized = false;
    return false;
  }

  CefBrowserSettings browser_settings;
  // With nothing to restore and no configured home page, the first tab is the
  // start page rather than a blank document, matching macOS and the `+` button.
  const std::string first_url = config.restored_tabs.empty() ?
      (config.initial_url.empty() ? std::string(kStartPageUrl) : config.initial_url)
      : config.restored_tabs.front().url;
  // The first tab is created here rather than through CreateTabOnUi because it
  // is what establishes `browser`. It still has to be rebound to its restored
  // partition, or a restored session would silently lose its isolation.
  CefRefPtr<CefRequestContext> first_context;
  std::optional<std::string> first_partition;
  std::optional<std::string> first_name;
  if (!config.restored_tabs.empty()) {
    const DesktopEngine::RestoredTab& first = config.restored_tabs.front();
    first_name = first.name;
    if (first.partition) {
      if (auto* entry = partitions.Acquire(*first.partition, first.persistent)) {
        // Startup owns the UI thread outright and is not inside a CEF callback,
        // so it is the one place that can pump the loop while a store loads.
        if (WaitForPartition(entry)) {
          first_context = entry->context;
          first_partition = entry->id;
        }
      }
    }
  }
  browser = CefBrowserHost::CreateBrowserSync(
      window_info,
      client.get(),
      first_url,
      browser_settings,
      nullptr,
      first_context);
  if (browser) {
    Tab initial;
    initial.id = config.restored_tabs.empty() ? "tab-1" : config.restored_tabs.front().id;
    initial.browser = browser;
    initial.devtools = NewDevToolsSession(browser);
    initial.url = first_url;
    initial.name = first_name;
    initial.partition = first_partition;
    tabs.push_back(std::move(initial));
    // tab-1 is already allocated for a fresh profile. The allocator is a
    // high-water mark, never a reconstruction from the currently open tabs.
    next_tab_id = config.restored_tabs.empty()
        ? 2
        : std::max<std::uint64_t>(config.restored_next_tab_id, 2);
    for (std::size_t index = 1; index < config.restored_tabs.size(); ++index) {
      const DesktopEngine::RestoredTab& restored = config.restored_tabs[index];
      if (restored.partition) {
        if (auto* entry = partitions.Acquire(*restored.partition, restored.persistent)) {
          WaitForPartition(entry);
        }
      }
      NewTabRequest request;
      request.url = restored.url;
      request.name = restored.name;
      request.partition = restored.partition;
      request.persistent = restored.persistent;
      TabSnapshot ignored;
      CreateTabOnUi(request, &ignored, restored.id);
    }
    for (const auto& restored : config.restored_tabs) {
      if (restored.active) {
        if (auto* tab = FindTab(TabLease{restored.id, 1})) {
#if defined(_WIN32)
          if (browser && browser->GetHost()) ShowWindow(browser->GetHost()->GetWindowHandle(), SW_HIDE);
          if (tab->browser && tab->browser->GetHost()) ShowWindow(tab->browser->GetHost()->GetWindowHandle(), SW_SHOW);
#endif
          browser = tab->browser;
        }
        break;
      }
    }
    UpdateActiveState();
  } else {
    last_error = "Chromium did not create the initial browser";
    app = nullptr;
    client = nullptr;
    CefShutdown();
    initialized = false;
    return false;
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

bool DesktopEngine::Impl::Shutdown() {
  if (!initialized) {
    return true;
  }
  shutting_down = true;
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
    last_error = "Chromium browser shutdown did not complete";
    return false;
  }
  browser = nullptr;
  client = nullptr;
  app = nullptr;
  // Every CEF reference has to be gone before CefShutdown. A request context
  // still held here is never asked to flush, and a persistent partition loses
  // everything written to it during the session.
  partitions.Clear();
  CefShutdown();
  initialized = false;
  return true;
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

DesktopEngine::DesktopEngine()
    : renderer_(std::make_unique<CefRenderer>()),
      impl_(std::make_shared<Impl>(renderer_.get())) {}

DesktopEngine::~DesktopEngine() = default;

bool DesktopEngine::Initialize(const Config& config) {
  return impl_->Initialize(config);
}

bool DesktopEngine::Shutdown() {
  return impl_->Shutdown();
}

void DesktopEngine::DoMessageLoopWork() {
  impl_->DoMessageLoopWork();
}

const std::string& DesktopEngine::last_error() const {
  return impl_->last_error;
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
  const auto impl = impl_;
  return impl->RunOnUi([impl, width, height] {
    impl->viewport.width = std::max(1, width);
    impl->viewport.height = std::max(1, height);
    if (impl->browser && impl->browser->GetHost()) impl->browser->GetHost()->WasResized();
    return BrowserControlResult::Success();
  }, std::chrono::seconds(2)).ok;
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


}  // namespace kelpie
