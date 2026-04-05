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

  bool Start(int preferred_port, RequestHandler handler, std::string* error);
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
  std::thread thread_;
};

}  // namespace kelpie::linuxapp
