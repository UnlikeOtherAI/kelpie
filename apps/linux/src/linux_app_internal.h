#pragma once

#include <atomic>
#include <chrono>
#include <filesystem>
#include <mutex>
#include <string>

#include "device_info_linux.h"
#include "http_server.h"
#include "linux_app.h"
#include "mdns_avahi.h"
#include "mollotov/bookmark_store.h"
#include "mollotov/desktop_engine.h"
#include "mollotov/console_store.h"
#include "mollotov/handler_context.h"
#include "mollotov/history_store.h"
#include "mollotov/mcp_registry.h"
#include "mollotov/network_traffic_store.h"
#include "mollotov/renderer_interface.h"
#include "stub_renderer.h"

namespace mollotov::linuxapp {

struct LinuxApp::Impl {
  AppConfig config;
  int argc = 0;
  char** argv = nullptr;
  std::unique_ptr<StubRenderer> stub_renderer;
  mollotov::DesktopEngine desktop_engine;
  mollotov::RendererInterface* renderer = nullptr;
  mollotov::HandlerContext handler_context;
  mollotov::BookmarkStore bookmarks;
  mollotov::HistoryStore history;
  mollotov::ConsoleStore console;
  mollotov::NetworkTrafficStore network;
  mollotov::McpRegistry registry;
  DeviceInfoLinux device_info;
  HttpServer http_server;
  MdnsAvahi mdns;
  bool running = false;
  bool shutdown_requested = false;
  int bound_port = 0;
  std::string pending_toast;
  mutable std::mutex toast_mutex;
  std::chrono::steady_clock::time_point started_at = std::chrono::steady_clock::now();
  std::string version = MOLLOTOV_LINUX_VERSION;
  std::string mdns_status = "inactive";
  bool browser_initialized = false;
  bool browser_hosted = false;
  std::atomic<bool> desired_fullscreen{false};
  std::atomic<bool> current_fullscreen{false};

  explicit Impl(AppConfig app_config, int argc_value, char** argv_value);

  void LoadStores();
  void PersistStores() const;
  void RecordNavigation(const std::string& url);
};

std::string ReadTextFile(const std::filesystem::path& path);
void WriteTextFile(const std::filesystem::path& path, const std::string& contents);
std::string CategoryForFilter(const nlohmann::json& entry);

}  // namespace mollotov::linuxapp
