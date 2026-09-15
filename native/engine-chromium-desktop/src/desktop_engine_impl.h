#pragma once

#include <functional>
#include <mutex>
#include <string>
#include <vector>

#include "include/cef_app.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "kelpie/desktop_engine.h"
#include "desktop_devtools.h"

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
  };

  CefRefPtr<CefClient> client;
  CefRefPtr<CefBrowser> browser;
  std::vector<Tab> tabs;
  std::uint64_t next_tab_id = 1;

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

  Tab* FindTab(const TabLease& lease);
  Tab* FindTab(CefRefPtr<CefBrowser> browser);
  Tab* ActiveTab();
  TabSnapshot Snapshot(const Tab& tab) const;
  BrowserControlResult RunOnUi(std::function<BrowserControlResult()> operation, Timeout timeout);
  BrowserControlResult CreateTabOnUi(const std::string& url, TabSnapshot* snapshot);
  void UpdateActiveState();
};

}  // namespace kelpie
