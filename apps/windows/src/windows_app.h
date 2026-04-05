#pragma once

#include <filesystem>
#include <mutex>
#include <memory>
#include <string>
#include <thread>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <httplib.h>
#include <nlohmann/json.hpp>

#include "kelpie/bookmark_store.h"
#include "kelpie/handler_context.h"
#include "kelpie/history_store.h"
#include "kelpie/mcp_registry.h"
#include "kelpie/network_traffic_store.h"

#include "device_info_windows.h"
#include "mdns_windows.h"
#include "settings_view.h"
#include "win32_browser_view.h"
#include "win32_shell.h"

namespace kelpie::windows {

struct AppConfig {
  int port = 8420;
  std::filesystem::path profile_dir;
  std::string initial_url = "https://example.com";
  int width = 1920;
  int height = 1080;
  bool port_overridden = false;
  bool profile_dir_overridden = false;
  bool url_overridden = false;
  bool width_overridden = false;
  bool height_overridden = false;
};

class WindowsApp final : public ShellDelegate, public BrowserStateObserver {
 public:
  WindowsApp(HINSTANCE instance, AppConfig config);
  ~WindowsApp();

  int Run(int show_command);

  void OnNavigateRequested(const std::string& url) override;
  void OnBackRequested() override;
  void OnForwardRequested() override;
  void OnReloadRequested() override;
  void OnOpenSettingsRequested() override;
  std::string GetBookmarksJson() const override;
  std::string GetHistoryJson() const override;
  std::string GetNetworkJson() const override;
  SettingsValues CurrentSettings() const override;
  void OnWindowCloseRequested() override;

  void OnBrowserStateChanged(const BrowserState& state) override;

 private:
  using json = nlohmann::json;

  void ResolveProfileDirectory();
  void LoadSettings();
  void SaveSettings() const;
  void LoadStores();
  void SaveStores() const;
  void ApplySettings(const SettingsValues& settings);
  bool InitializeCommonControls() const;
  bool InitializeBrowserRuntime();
  void ShutdownBrowserRuntime();
  bool CreateShell(int show_command);
  void StartHttpServer();
  void StopHttpServer();
  std::uint16_t FindAvailablePort(std::uint16_t preferred_port) const;
  void StartMdns();
  void StopMdns();
  DeviceInfo BuildDeviceInfo() const;
  json HandleApiMethod(const std::string& method, const json& body, int& status_code);
  json HandleSupportedMethod(const std::string& method, const json& body, int& status_code);
  json UnsupportedResponse(const std::string& method, int& status_code) const;
  json UnknownMethodResponse(const std::string& method, int& status_code) const;
  json CurrentUrlResponse() const;
  void RememberNavigation(const BrowserState& state);
  void RefreshDeviceInfo();
  std::wstring AppTitle() const;

  HINSTANCE instance_;
  AppConfig config_;
  std::atomic<bool> running_{true};
  std::atomic<bool> http_running_{false};

  BookmarkStore bookmark_store_;
  HistoryStore history_store_;
  NetworkTrafficStore network_store_;
  McpRegistry mcp_registry_;
  HandlerContext handler_context_;
  DeviceInfoWindows device_info_provider_;
  mutable DeviceInfo device_info_;
  BrowserState browser_state_;
  std::string last_recorded_url_;

  std::unique_ptr<Win32Shell> shell_;
  std::unique_ptr<Win32BrowserView> browser_view_;
  std::unique_ptr<SettingsView> settings_view_;
  std::unique_ptr<MdnsWindows> mdns_;

  std::unique_ptr<httplib::Server> http_server_;
  std::thread http_thread_;
};

}  // namespace kelpie::windows
