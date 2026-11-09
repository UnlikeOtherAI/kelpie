#include "http_server.h"
#include "kelpie/desktop_http_server.h"
#include <filesystem>
#include <fstream>
#include <sstream>

namespace kelpie::linuxapp {
HttpServer::HttpServer() : server_(std::make_unique<DesktopHttpServer>()) {}
HttpServer::~HttpServer() = default;

bool HttpServer::Start(int preferred_port, std::string control_token, RequestHandler handler,
                       std::string* error, bool approval_available) {
  if (running()) return true;
  for (int candidate = preferred_port; candidate < preferred_port + 50; ++candidate) {
    auto server = std::make_unique<DesktopHttpServer>();
    server->SetRequestHandler([handler](std::string_view method, const json& body) {
      int status = 200;
      auto result = handler ? handler(method, body, &status) : json::object();
      return std::make_pair(status, std::move(result));
    });
    DesktopHttpServer::Config config;
    config.port = candidate;
    config.control_token = control_token;  // retained for older readiness-file clients
    config.approval_available = approval_available;
    config.debug_page = [] {
      std::error_code failure;
      const auto executable = std::filesystem::read_symlink("/proc/self/exe", failure);
      if (failure) return std::string();
      std::ifstream file(executable.parent_path() / "diagnostics" / "coordinate-calibration.html");
      std::ostringstream contents; contents << file.rdbuf(); return contents.str();
    };
    if (server->Start(config)) { server_ = std::move(server); return true; }
  }
  if (error) *error = "No available control port";
  return false;
}
void HttpServer::Stop() { server_->Stop(); }
bool HttpServer::running() const { return server_->IsRunning(); }
int HttpServer::port() const { return server_->bound_port(); }
PeerApprovalQueue& HttpServer::approvals() { return server_->approvals(); }
}  // namespace kelpie::linuxapp
