#pragma once

#include <atomic>
#include <functional>
#include <string>
#include <thread>

#include <nlohmann/json.hpp>

namespace kelpie::linuxapp {

class HttpServer {
 public:
  using json = nlohmann::json;
  using RequestHandler = std::function<json(std::string_view endpoint, const json& body, int* status_code)>;

  HttpServer();
  ~HttpServer();

  // Binds 127.0.0.1 only. Every POST /v1/* must carry
  // `Authorization: Bearer <control_token>`, the per-launch token published in
  // the profile's readiness file — the same contract as the CEF desktop build.
  bool Start(int preferred_port, std::string control_token, RequestHandler handler, std::string* error);
  void Stop();

  bool running() const;
  int port() const;

 private:
  void AcceptLoop();
  bool Bind(int preferred_port, std::string* error);

  std::atomic<bool> running_{false};
  int port_ = 0;
  int server_fd_ = -1;
  RequestHandler handler_;
  std::string control_token_;
  std::thread thread_;
};

}  // namespace kelpie::linuxapp
