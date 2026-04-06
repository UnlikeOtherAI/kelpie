#pragma once

#include <memory>
#include <string>

namespace kelpie {

class DesktopRouter;

class DesktopHttpServer {
 public:
  struct Config {
    std::string bind_host = "0.0.0.0";
    int port = 8420;
    int read_timeout_seconds = 30;
    int write_timeout_seconds = 30;
  };

  DesktopHttpServer();
  ~DesktopHttpServer();

  void SetRouter(const DesktopRouter* router);

  bool Start(const Config& config);
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
