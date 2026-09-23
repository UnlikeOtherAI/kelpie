#pragma once

#include <atomic>
#include <chrono>
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
#include "desktop_partition_registry.h"

namespace kelpie {

// Internal sentinel, never seen by a caller: CreateTabOnUi reports a partition
// whose store is still loading, and DesktopEngine::CreateTab either retries
// past it or rewrites it into a real error.
inline constexpr const char* kPartitionNotReady = "PARTITION_NOT_READY";

// Whether `url` can be loaded into a tab. Defined in desktop_engine_control.cpp.
bool IsNavigableUrl(const std::string& url);

// What is left of `timeout` since `started`, never negative. Shared by the
// engine's operations that make more than one native call.
inline DesktopBrowserControl::Timeout RemainingTimeout(std::chrono::steady_clock::time_point started,
                                                       DesktopBrowserControl::Timeout timeout) {
  const auto elapsed = std::chrono::duration_cast<DesktopBrowserControl::Timeout>(
      std::chrono::steady_clock::now() - started);
  return elapsed >= timeout ? DesktopBrowserControl::Timeout::zero() : timeout - elapsed;
}

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
    // Main-frame navigations for wait-for-navigation, whoever started them.
    NavigationTracker navigation;
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
  DesktopPartitionRegistry partitions;

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
  // A tab's DevTools session, attached so its Network events reach network_sink.
  CefRefPtr<DesktopDevToolsSession> NewDevToolsSession(CefRefPtr<CefBrowser> browser);
  Tab* ActiveTab();
  // Records a downloaded favicon against the tab and the host registry.
  void StoreFavicon(CefRefPtr<CefBrowser> browser, std::string png_base64);
  TabSnapshot Snapshot(const Tab& tab) const;
  BrowserControlResult RunOnUi(std::function<BrowserControlResult()> operation, Timeout timeout);
  BrowserControlResult CreateTabOnUi(const NewTabRequest& request, TabSnapshot* snapshot,
                                     std::optional<std::string> restored_id = std::nullopt);
  // An empty `url` opens `kelpie://start`.
  BrowserControlResult CreateTabOnUi(const std::string& url, TabSnapshot* snapshot,
                                     std::optional<std::string> restored_id = std::nullopt) {
    NewTabRequest request;
    request.url = url;
    return CreateTabOnUi(request, snapshot, std::move(restored_id));
  }
  // Pumps the CEF loop until a partition's store has loaded. Only callable
  // from the UI thread outside a CEF callback -- startup, in practice.
  bool WaitForPartition(DesktopPartitionRegistry::Entry* entry);
  // Rebuilds every partition's tab count from the live tab list and drops
  // entries no tab is bound to any more. Counts are never carried forward
  // from a previous read, so a crashed or force-closed tab cannot inflate one.
  void RecountPartitions();
  void UpdateActiveState();
};

// Begins `method` on the tab's DevTools session and waits for its reply, giving
// up early when `interrupted` reports that the reply can no longer arrive.
// Defined in desktop_engine_control.cpp; trusted input in
// desktop_engine_page.cpp is the caller that passes `interrupted`.
BrowserControlResult RunDevTools(const std::shared_ptr<DesktopEngine::Impl>& impl, TabLease lease,
                                 std::string method, const nlohmann::json& params,
                                 nlohmann::json* output, DesktopBrowserControl::Timeout timeout,
                                 const std::function<bool()>& interrupted = {});

}  // namespace kelpie
