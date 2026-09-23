#pragma once

#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

#include "kelpie/desktop_browser_control.h"
#include "kelpie/cef_renderer.h"
#include "kelpie/favicon_registry.h"

namespace kelpie {

class DesktopEngine final : public DesktopBrowserControl {
 public:
  enum class Mode {
    kWindowed = 0,
    kOffscreen,
  };

  struct Size {
    int width = 1280;
    int height = 720;
  };

  struct RestoredTab {
    std::string id;
    std::string url;
    bool active = false;
    std::optional<std::string> name;
    std::optional<std::string> partition;
    bool persistent = true;
  };

  struct Config {
    Mode mode = Mode::kOffscreen;
    Size viewport;
    // On Windows CEF receives the application HINSTANCE. Other platforms use
    // argc/argv. Keeping both avoids platform-specific runtime entry points.
    void* process_instance = nullptr;
    // Supplied by CEF bootstrap.exe on Windows. It must be passed unchanged
    // to CefInitialize so Chromium subprocesses remain sandboxed.
    void* sandbox_info = nullptr;
    int argc = 0;
    char** argv = nullptr;
    std::string initial_url;
    std::vector<RestoredTab> restored_tabs;
    std::uint64_t restored_next_tab_id = 1;
    std::string cache_path;
    // The parent directory CEF requires every cache path to share: CefSettings
    // and every CefRequestContextSettings cache_path must sit under it. When
    // it is empty CEF defaults it to cache_path, and any partition store
    // outside that tree is silently ignored and falls back to memory.
    std::string root_cache_path;
    // Parent directory for the per-partition stores; each persistent partition
    // gets a subdirectory named after its id. It must live under
    // root_cache_path. Empty forces every partition in-memory, which is what a
    // profile-less test shell wants.
    std::string partitions_path;
    std::string user_agent;
    std::string browser_subprocess_path;
    std::string resources_dir_path;
    std::string locales_dir_path;
    bool external_message_pump = true;
    std::function<void(void*)> configure_window_info;
    std::function<void(void*, const std::string&)> configure_tab_window_info;
    // Supplies the `kelpie://start` data payload. The engine owns no stores, so
    // the application wires this to its BookmarkStore and HistoryStore. Called
    // on the CEF IO thread; the implementation must be thread-safe.
    std::function<std::string()> start_page_data_supplier;
  };

  struct SessionState {
    std::uint64_t next_tab_id = 1;
    std::vector<RestoredTab> tabs;
  };

  using NavigationState = BrowserNavigationState;

  struct ViewportState {
    int width = 1280;
    int height = 720;
    double device_pixel_ratio = 1.0;
    bool offscreen = true;
  };

  using JsonEventSink = std::function<void(const nlohmann::json&)>;
  using NavigationSink = std::function<void(const std::string&, const std::string&)>;

  DesktopEngine();
  ~DesktopEngine();

  bool Initialize(const Config& config);
  bool Shutdown();
  void DoMessageLoopWork();
  const std::string& last_error() const;
  bool IsActiveNativeBrowserAttached(void* parent_window, Timeout timeout);

  bool is_initialized() const;
  bool is_offscreen() const;

  // Favicons downloaded this session, keyed by host. Survives tab close, which
  // is what the start page's Favourites and Recent lists need. The stub
  // configuration keeps an always-empty registry so callers need no #if.
  FaviconRegistry& favicons();

  ViewportState viewport() const;
  bool ResizeViewport(int width, int height);
  bool SendFocusEvent(bool focused);
  bool SendMouseMoveEvent(int x, int y, bool mouse_leave);
  bool SendMouseClickEvent(int x, int y, int button, bool mouse_up, int click_count);
  bool SendMouseWheelEvent(int x, int y, int delta_x, int delta_y);

  void SetConsoleSink(JsonEventSink sink);
  void SetNetworkSink(JsonEventSink sink);
  void SetNavigationSink(NavigationSink sink);

  CefRenderer& renderer();
  const CefRenderer& renderer() const;

  BrowserControlResult GetTabs(std::vector<TabSnapshot>* tabs, Timeout timeout) override;
  BrowserControlResult GetSessionState(SessionState* state, Timeout timeout);
  BrowserControlResult GetNavigationState(TabLease lease, NavigationState* state, Timeout timeout) override;
  BrowserControlResult MarkNavigationAction(TabLease lease, Timeout timeout) override;
  BrowserControlResult ResolveTab(const std::optional<std::string>& tab_id,
                                  const std::optional<std::uint64_t>& generation,
                                  TabLease* lease,
                                  Timeout timeout) override;
  BrowserControlResult CreateTab(const NewTabRequest& request, TabSnapshot* tab,
                                 Timeout timeout) override;
  using DesktopBrowserControl::CreateTab;
  BrowserControlResult GetPartitions(std::vector<PartitionInfo>* partitions,
                                     Timeout timeout) override;
  BrowserControlResult DeletePartition(const std::string& id, PartitionDeletion* deletion,
                                       Timeout timeout) override;
  BrowserControlResult ActivateTab(TabLease lease, Timeout timeout) override;
  BrowserControlResult CloseTab(TabLease lease, Timeout timeout) override;
  BrowserControlResult Navigate(std::optional<TabLease> lease,
                                std::string url,
                                TabSnapshot* tab,
                                Timeout timeout) override;
  BrowserControlResult Back(TabLease lease, TabSnapshot* tab, Timeout timeout) override;
  BrowserControlResult Forward(TabLease lease, TabSnapshot* tab, Timeout timeout) override;
  BrowserControlResult Reload(TabLease lease, TabSnapshot* tab, Timeout timeout) override;
  BrowserControlResult StopLoading(TabLease lease, TabSnapshot* tab, Timeout timeout);
  BrowserControlResult Evaluate(TabLease lease,
                                std::string script,
                                Json* value,
                                Timeout timeout) override;
  BrowserControlResult Screenshot(TabLease lease,
                                  const BrowserScreenshotOptions& options,
                                  BrowserScreenshot* image,
                                  Timeout timeout) override;
  BrowserControlResult GetCookies(TabLease lease,
                                  const Json& query,
                                  Json* cookies,
                                  Timeout timeout) override;
  BrowserControlResult SetCookies(TabLease lease,
                                  const Json& cookies,
                                  Json* result,
                                  Timeout timeout) override;
  BrowserControlResult DeleteCookies(TabLease lease,
                                     const Json& query,
                                     Json* result,
                                     Timeout timeout) override;
  BrowserControlResult DispatchTrustedInput(TabLease lease,
                                            const Json& input,
                                            Json* result,
                                            Timeout timeout) override;
  BrowserControlResult GetDialog(TabLease lease, Json* dialog, Timeout timeout) override;
  BrowserControlResult HandleDialog(TabLease lease,
                                    const Json& action,
                                    Json* result,
                                    Timeout timeout) override;
  BrowserControlResult DevTools(TabLease lease,
                                std::string method,
                                const Json& params,
                                Json* result,
                                Timeout timeout) override;

  class Impl;

 private:
  std::unique_ptr<CefRenderer> renderer_;
  std::shared_ptr<Impl> impl_;
};

}  // namespace kelpie
