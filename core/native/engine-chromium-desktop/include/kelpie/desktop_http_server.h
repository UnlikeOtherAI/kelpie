#pragma once

#include <memory>
#include <string>

namespace kelpie {

class DesktopRouter;
class DesktopMcpServer;

class DesktopHttpServer {
 public:
  struct Config {
    std::string bind_host = "127.0.0.1";
    int port = 8420;
    int read_timeout_seconds = 30;
    int write_timeout_seconds = 30;
    std::size_t max_body_bytes = 1024 * 1024;
    std::string control_token;
    std::string device_id;
    std::string platform = "linux";
    std::string engine = "chromium";
    std::string server_name = "kelpie-desktop";
    std::string server_version = "0.0.1";
  };

  DesktopHttpServer();
  ~DesktopHttpServer();

  void SetRouter(const DesktopRouter* router);
  void SetMcpServer(const DesktopMcpServer* server);

  bool Start(const Config& config);
  // Close the listener without joining its worker. Existing requests retire before
  // IsDrained becomes true; Windows keeps its owner pump running in the meantime.
  void BeginDrain();
  bool IsDrained() const;
  void Stop();

  bool IsRunning() const;
  int bound_port() const;

  // NOTE: The Swift HTTPServer (ServerState) implements port fallback logic
  // (tries port+1, port+2, etc.) when the preferred port is busy. If both
  // servers ever run simultaneously, this C++ side should also attempt fallback.
  // Currently only one server runs at a time so this is not yet needed.

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace kelpie
