#pragma once

#include <memory>
#include <string>
#include <functional>
#include <string_view>
#include "kelpie/peer_approval.h"

namespace kelpie {

class DesktopRouter;
class DesktopMcpServer;

class DesktopHttpServer {
 public:
  struct Config {
    std::string bind_host = "::";
    bool approval_available = false;
    int port = 8420;
    int read_timeout_seconds = 5;
    int write_timeout_seconds = 30;
    std::size_t max_body_bytes = 1024 * 1024;
    std::string control_token;
    std::string device_id;
    std::string platform = "linux";
    std::string engine = "chromium";
    std::string server_name = "kelpie-desktop";
    std::string server_version = "0.0.1";
    std::function<std::string()> debug_page;
  };

  using RequestHandler = std::function<std::pair<int, nlohmann::json>(std::string_view, const nlohmann::json&)>;
  explicit DesktopHttpServer(std::filesystem::path trust_path = PeerTrustStore::DefaultPath());
  ~DesktopHttpServer();

  void SetRouter(const DesktopRouter* router);
  void SetMcpServer(const DesktopMcpServer* server);
  // The Linux no-CEF shell delegates its supported routes through the same transport.
  void SetRequestHandler(RequestHandler handler);

  bool Start(const Config& config);
  // Close the listener without joining its worker. Existing requests retire before
  // IsDrained becomes true; Windows keeps its owner pump running in the meantime.
  void BeginDrain();
  bool IsDrained() const;
  void Stop();

  bool IsRunning() const;
  int bound_port() const;
  PeerApprovalQueue& approvals();

  // NOTE: The Swift HTTPServer (ServerState) implements port fallback logic
  // (tries port+1, port+2, etc.) when the preferred port is busy. If both
  // servers ever run simultaneously, this C++ side should also attempt fallback.
  // Currently only one server runs at a time so this is not yet needed.

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace kelpie
