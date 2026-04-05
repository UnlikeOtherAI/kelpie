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

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace kelpie
