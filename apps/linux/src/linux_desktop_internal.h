#pragma once
#include "linux_app.h"
#include "device_info_linux.h"
#include "profile_session.h"
#include "account_service.h"
#include "kelpie/desktop_app.h"
#include "kelpie/desktop_http_server.h"
#include "kelpie/desktop_router.h"
#include <atomic>
#include <mutex>

namespace kelpie::linuxapp {
struct LinuxApp::Impl final : DeviceInfoProvider {
  AppConfig config;
  int argc; char** argv;
  ProfileSession profile;
  DeviceInfoLinux device;
  mutable DesktopApp desktop;
  account::AccountService account;
  std::atomic<bool> running{true}, closing{false}, fullscreen{false}, desired_fullscreen{false};
  std::atomic<int> requested_width{0},requested_height{0};
  std::atomic<bool> started{false};
  std::atomic<int> view_width{1},view_height{1};
  mutable std::mutex state_mutex;
  std::string home,toast,last_session,last_bookmarks,last_history;
  std::chrono::steady_clock::time_point last_save{};
  Impl(AppConfig settings,int count,char** args);
  nlohmann::json GetDeviceInfo() const override;
  StringMap GetMdnsMetadata() const override { return {}; }
  void LoadSession(DesktopEngine::Config& engine);
  void Save();
};
std::string ReadProfile(const std::filesystem::path& path);
}  // namespace kelpie::linuxapp
