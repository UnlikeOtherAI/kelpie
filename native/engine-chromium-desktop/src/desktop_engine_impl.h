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
#include "desktop_devtools.h"
#include "desktop_partition_registry.h"

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
    // Caller-supplied label and storage binding. Both absent for an ordinary
    // tab in the default shared store.
    std::optional<std::string> name;
    std::optional<std::string> partition;
    bool loading = false;
    bool can_go_back = false;
    bool can_go_forward = false;
    std::uint64_t navigation_requested = 0;
    std::uint64_t navigation_completed = 0;
    std::string navigation_error;
    // CEF retains the browser until OnBeforeClose. A close request must not
    // erase this owner early, otherwise cancellation and shutdown can leave a
    // live callback pointing at destroyed state.
    bool closing = false;
  };

  CefRefPtr<CefClient> client;
  CefRefPtr<CefBrowser> browser;
  std::vector<Tab> tabs;
  std::uint64_t next_tab_id = 1;
  DesktopPartitionRegistry partitions;

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
  TabSnapshot Snapshot(const Tab& tab) const;
  BrowserControlResult RunOnUi(std::function<BrowserControlResult()> operation, Timeout timeout);
  BrowserControlResult CreateTabOnUi(const NewTabRequest& request, TabSnapshot* snapshot,
                                     std::optional<std::string> restored_id = std::nullopt);
  BrowserControlResult CreateTabOnUi(const std::string& url, TabSnapshot* snapshot,
                                     std::optional<std::string> restored_id = std::nullopt) {
    NewTabRequest request;
    request.url = url;
    return CreateTabOnUi(request, snapshot, std::move(restored_id));
  }
  // Rebuilds every partition's tab count from the live tab list and drops
  // entries no tab is bound to any more. Counts are never carried forward
  // from a previous read, so a crashed or force-closed tab cannot inflate one.
  void RecountPartitions();
  void UpdateActiveState();
};

}  // namespace kelpie
