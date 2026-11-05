#pragma once

#include <functional>
#include <memory>
#include <string>
#include <string_view>
#include <nlohmann/json.hpp>
#include "kelpie/peer_approval.h"

namespace kelpie { class DesktopHttpServer; }
namespace kelpie::linuxapp {

// The no-CEF shell supplies handlers, not a second HTTP parser or auth policy.
class HttpServer {
 public:
  using json = nlohmann::json;
  using RequestHandler = std::function<json(std::string_view, const json&, int*)>;
  HttpServer();
  ~HttpServer();
  bool Start(int preferred_port, std::string control_token, RequestHandler handler,
             std::string* error, bool approval_available = false);
  void Stop();
  bool running() const;
  int port() const;
  PeerApprovalQueue& approvals();
 private:
  std::unique_ptr<DesktopHttpServer> server_;
};
}  // namespace kelpie::linuxapp
