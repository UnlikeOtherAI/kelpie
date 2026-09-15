#pragma once

#include <memory>
#include <string>

#include <nlohmann/json.hpp>

#include "kelpie/constants.h"
#include "kelpie/desktop_engine.h"
#include "kelpie/platform.h"

namespace kelpie {

class DesktopHttpServer;
class DesktopMdns;
class DesktopMcpServer;
class DesktopRouter;
class McpRegistry;

class DeviceInfoProvider {
 public:
  virtual ~DeviceInfoProvider() = default;

  virtual nlohmann::json GetDeviceInfo() const = 0;
  virtual StringMap GetMdnsMetadata() const = 0;
};

class DesktopApp {
 public:
  struct Config {
    Platform platform = Platform::kLinux;
    std::string engine_name = "chromium";
    int port = kDefaultPort;
    std::string app_name = "kelpie-desktop";
    std::string app_version = "0.0.1";
    bool start_stdio_mcp = false;
    std::string bind_host = "127.0.0.1";
    std::string control_token;
    std::string device_id;
    std::function<BrowserControlResult(bool enabled)> set_native_fullscreen;
    std::function<BrowserControlResult(bool* enabled)> get_native_fullscreen;
    std::function<BrowserControlResult()> request_shutdown;
    std::function<BrowserControlResult(std::string url)> set_home;
    std::function<BrowserControlResult(std::string* url)> get_home;
    std::function<BrowserControlResult(std::string message)> show_native_toast;
    // Browser-wide viewport operations. Windows supplies these callbacks from
    // its owner thread; the shared fallback is for non-Windows test shells.
    std::function<nlohmann::json()> viewport_supplier;
    std::function<bool(int width, int height)> resize_viewport;
    std::function<void()> reset_viewport;
    DesktopEngine::Config engine;
    DesktopMdns* mdns = nullptr;
    DeviceInfoProvider* device_info_provider = nullptr;
  };

  DesktopApp();
  ~DesktopApp();

  bool Start(const Config& config);
  void Stop();
  void Tick();

  bool is_running() const;

  DesktopEngine& engine();
  DesktopRouter& router();
  DesktopHttpServer& http_server();
  DesktopMcpServer& mcp_server();
  McpRegistry& mcp_registry();

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace kelpie
#include <functional>
