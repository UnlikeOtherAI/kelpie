#pragma once

#include <functional>
#include <memory>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

#include "kelpie/desktop_browser_control.h"
#include "kelpie/cef_renderer.h"

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
    std::string cache_path;
    std::string user_agent;
    std::string browser_subprocess_path;
    std::string resources_dir_path;
    std::string locales_dir_path;
    bool external_message_pump = true;
    std::function<void(void*)> configure_window_info;
    std::function<void(void*, const std::string&)> configure_tab_window_info;
  };

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
  void Shutdown();
  void DoMessageLoopWork();

  bool is_initialized() const;
  bool is_offscreen() const;

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
  BrowserControlResult ResolveTab(const std::optional<std::string>& tab_id,
                                  const std::optional<std::uint64_t>& generation,
                                  TabLease* lease,
                                  Timeout timeout) override;
  BrowserControlResult CreateTab(std::string url, TabSnapshot* tab, Timeout timeout) override;
  BrowserControlResult ActivateTab(TabLease lease, Timeout timeout) override;
  BrowserControlResult CloseTab(TabLease lease, Timeout timeout) override;
  BrowserControlResult Navigate(std::optional<TabLease> lease,
                                std::string url,
                                TabSnapshot* tab,
                                Timeout timeout) override;
  BrowserControlResult Back(TabLease lease, TabSnapshot* tab, Timeout timeout) override;
  BrowserControlResult Forward(TabLease lease, TabSnapshot* tab, Timeout timeout) override;
  BrowserControlResult Reload(TabLease lease, TabSnapshot* tab, Timeout timeout) override;
  BrowserControlResult Evaluate(TabLease lease,
                                std::string script,
                                Json* value,
                                Timeout timeout) override;
  BrowserControlResult Screenshot(TabLease lease,
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
