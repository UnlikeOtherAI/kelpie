#pragma once

#include <iosfwd>
#include <memory>
#include <string>

#include <nlohmann/json.hpp>

#include "kelpie/platform.h"

namespace kelpie {

class DesktopRouter;
class McpRegistry;

class DesktopMcpServer {
 public:
  using json = nlohmann::json;

  struct Config {
    Platform platform = Platform::kLinux;
    std::string engine = "chromium";
    std::string server_name = "kelpie-desktop";
    std::string server_version = "0.0.1";
    std::istream* input = nullptr;
    std::ostream* output = nullptr;
  };

  DesktopMcpServer();
  ~DesktopMcpServer();

  void SetRouter(const DesktopRouter* router);
  void SetRegistry(const McpRegistry* registry);

  bool Run(const Config& config);
  json HandleRequest(const json& request, const Config& config) const;

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace kelpie
