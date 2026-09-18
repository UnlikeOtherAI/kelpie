#pragma once

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

#include "include/cef_app.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "kelpie/desktop_engine.h"
#include "kelpie/favicon_registry.h"
#include "desktop_devtools.h"

namespace kelpie {

class DesktopCefClient;

class DesktopEngine::Impl : public std::enable_shared_from_this<DesktopEngine::Impl> {
 public:
  explicit Impl(CefRenderer* renderer);

  bool Initialize(const DesktopEngine::Config& next_config);
  bool Shutdown();
  void DoMessageLoopWork();
  std::string EvaluateJs(const std::string& script);

  DesktopEngine::ViewportState viewport;
  DesktopEngine::Config config;
  CefRenderer* renderer = nullptr;
  CefRefPtr<CefApp> app;
  struct Tab {
    std::string id;
    std::uint64_t generation = 1;
    CefRefPtr<CefBrowser> browser;
    CefRefPtr<DesktopDevToolsSession> devtools;
    DesktopDialogAdapter dialogs;
    std::string url = "about:blank";
    std::string title;
    bool loading = false;
    bool can_go_back = false;
    bool can_go_forward = false;
    std::uint64_t navigation_requested = 0;
    std::uint64_t navigation_completed = 0;
    std::string navigation_error;
    // The icon URL currently being downloaded, so a repeated
    // OnFaviconURLChange for the same page does not re-request it.
    std::string favicon_url;
    // Immutable once set; replaced wholesale when a new icon arrives, so
    // TabSnapshot can share it without copying.
    std::shared_ptr<const std::string> favicon_png_base64;
    // CEF retains the browser until OnBeforeClose. A close request must not
    // erase this owner early, otherwise cancellation and shutdown can leave a
    // live callback pointing at destroyed state.
    bool closing = false;
  };

  CefRefPtr<CefClient> client;
  CefRefPtr<CefBrowser> browser;
  std::vector<Tab> tabs;
  std::uint64_t next_tab_id = 1;

  // Host-keyed favicons for every site visited this session. Outlives any one
  // tab, which is what the start page's Favourites and Recent lists need.
  FaviconRegistry favicons;

  DesktopEngine::JsonEventSink console_sink;
  DesktopEngine::JsonEventSink network_sink;
  DesktopEngine::NavigationSink navigation_sink;

  bool initialized = false;
  std::atomic<bool> shutting_down = false;
  std::string last_error;
  bool loading = false;
  bool can_go_back = false;
  bool can_go_forward = false;
  std::string current_url = "about:blank";
  std::string current_title;
  std::vector<std::uint8_t> snapshot_bytes;
  std::mutex mutex;

  Tab* FindTab(const TabLease& lease);
  Tab* FindTab(CefRefPtr<CefBrowser> browser);
  Tab* ActiveTab();
  // Records a downloaded favicon against the tab and the host registry.
  void StoreFavicon(CefRefPtr<CefBrowser> browser, std::string png_base64);
  TabSnapshot Snapshot(const Tab& tab) const;
  BrowserControlResult RunOnUi(std::function<BrowserControlResult()> operation, Timeout timeout);
  BrowserControlResult CreateTabOnUi(const std::string& url, TabSnapshot* snapshot, std::optional<std::string> restored_id = std::nullopt);
  void UpdateActiveState();
};

}  // namespace kelpie
