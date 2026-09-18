#pragma once

#include <filesystem>
#include <cstdint>
#include <mutex>
#include <memory>
#include <string>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <nlohmann/json.hpp>

#include "kelpie/bookmark_store.h"
#include "kelpie/desktop_app.h"
#include "kelpie/history_store.h"
#include "kelpie/network_traffic_store.h"

#include "device_info_windows.h"
#include "profile_session.h"
#include "session_snapshot.h"
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
  bool mcp_stdio = false;
  std::filesystem::path readiness_path;
  void* sandbox_info = nullptr;
  void* cef_process_instance = nullptr;
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
  std::string GetTabsJson() const override;
  std::optional<std::wstring> BestUrlCompletion(std::wstring_view typed) const override;
  SettingsValues CurrentSettings() const override;
  void OnCreateTabRequested() override;
  void OnActivateTabRequested(std::string id, std::uint64_t generation) override;
  void OnCloseTabRequested(std::string id, std::uint64_t generation) override;
  void OnWindowCloseRequested() override;

  void OnBrowserStateChanged(const BrowserState& state) override;

 private:
  using json = nlohmann::json;

  void ResolveProfileDirectory();
  void LoadSettings();
  void SaveSettings() const;
  void LoadStores();
  void LoadSession();
  void SaveSession();
  void SaveStores();
  void ApplySettings(const SettingsValues& settings);
  bool InitializeCommonControls() const;
  bool InitializeDesktopRuntime();
  void ShutdownDesktopRuntime();
  void UpdateBrowserStateFromRuntime();
  bool CreateShell(int show_command);
  void RememberNavigation(const BrowserState& state);
  std::wstring AppTitle() const;

  HINSTANCE instance_;
  AppConfig config_;
  std::atomic<bool> running_{true};

  DeviceInfoWindows device_info_provider_;
  BrowserState browser_state_;
  std::uint64_t persistence_epoch_ = 0;
  SessionSnapshot session_snapshot_;
  std::mutex shell_state_mutex_;
  std::string home_url_;

  std::unique_ptr<Win32Shell> shell_;
  std::unique_ptr<Win32BrowserView> browser_view_;
  std::unique_ptr<SettingsView> settings_view_;
  std::unique_ptr<DesktopApp> desktop_app_;
  ProfileSession profile_session_;

};

}  // namespace kelpie::windows
