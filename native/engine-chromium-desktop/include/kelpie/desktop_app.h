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
