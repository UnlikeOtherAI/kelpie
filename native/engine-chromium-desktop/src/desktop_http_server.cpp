#include "kelpie/desktop_http_server.h"

#include <thread>

#include <httplib.h>
#include <nlohmann/json.hpp>

#include "kelpie/desktop_router.h"

namespace kelpie {
namespace {

void AddCorsHeaders(httplib::Response& response) {
  response.set_header("Access-Control-Allow-Origin", "*");
  response.set_header("Access-Control-Allow-Headers", "Content-Type");
  response.set_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  response.set_header("Content-Type", "application/json");
}

}  // namespace

class DesktopHttpServer::Impl {
 public:
  const DesktopRouter* router = nullptr;
  httplib::Server server;
  std::thread server_thread;
  int bound_port = 0;
  bool running = false;
};

DesktopHttpServer::DesktopHttpServer() : impl_(std::make_unique<Impl>()) {}

DesktopHttpServer::~DesktopHttpServer() {
  Stop();
}

void DesktopHttpServer::SetRouter(const DesktopRouter* router) {
  impl_->router = router;
}

bool DesktopHttpServer::Start(const Config& config) {
  if (impl_->router == nullptr || impl_->running) {
    return false;
  }

  impl_->server.Get("/health", [](const httplib::Request&, httplib::Response& response) {
    AddCorsHeaders(response);
    response.status = 200;
    response.set_content(R"({"status":"ok"})", "application/json");
  });

  impl_->server.Options(R"(.*)", [](const httplib::Request&, httplib::Response& response) {
    AddCorsHeaders(response);
    response.status = 204;
  });

  impl_->server.Post(R"(/v1/(.+))", [this](const httplib::Request& request,
                                            httplib::Response& response) {
    AddCorsHeaders(response);
    nlohmann::json body = nlohmann::json::object();
    if (!request.body.empty()) {
      try {
        body = nlohmann::json::parse(request.body);
      } catch (...) {
        response.status = 400;
        response.set_content(
            R"({"success":false,"error":{"code":"INVALID_JSON","message":"Request body must be valid JSON"}})",
            "application/json");
        return;
      }
    }

    const std::string method = request.matches[1].str();
    const DesktopRouter::Result result = impl_->router->Dispatch(method, body);
    response.status = result.status_code;
    response.set_content(result.body.dump(), "application/json");
  });

  impl_->server.set_read_timeout(config.read_timeout_seconds, 0);
  impl_->server.set_write_timeout(config.write_timeout_seconds, 0);
  impl_->bound_port = impl_->server.bind_to_port(config.bind_host.c_str(), config.port);
  if (impl_->bound_port <= 0) {
    return false;
  }

  impl_->running = true;
  impl_->server_thread = std::thread([this]() {
    impl_->server.listen_after_bind();
  });
  return true;
}

void DesktopHttpServer::Stop() {
  if (!impl_->running) {
    return;
  }
  impl_->server.stop();
  if (impl_->server_thread.joinable()) {
    impl_->server_thread.join();
  }
  impl_->running = false;
  impl_->bound_port = 0;
}

bool DesktopHttpServer::IsRunning() const {
  return impl_->running;
}

int DesktopHttpServer::bound_port() const {
  return impl_->bound_port;
}

}  // namespace kelpie
