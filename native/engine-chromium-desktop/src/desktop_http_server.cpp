#include "kelpie/desktop_http_server.h"

#include <algorithm>
#include <thread>

#include <httplib.h>
#include <nlohmann/json.hpp>

#include "kelpie/desktop_mcp_server.h"
#include "kelpie/desktop_router.h"
#include "kelpie/platform.h"

namespace kelpie {
namespace {

constexpr const char* kMcpProtocolVersion = "2025-06-18";

void Json(httplib::Response& response, int status, const nlohmann::json& body) {
  response.status = status;
  response.set_content(body.dump(), "application/json");
}

bool IsLoopbackHost(const std::string& host) {
  const std::size_t separator = host.rfind(':');
  const std::string name = separator == std::string::npos ? host : host.substr(0, separator);
  return name == "127.0.0.1" || name == "localhost" || name == "[::1]";
}

bool HasJsonContentType(const httplib::Request& request) {
  const std::string content_type = request.get_header_value("Content-Type");
  const std::size_t separator = content_type.find(';');
  return content_type.substr(0, separator) == "application/json";
}

bool HasMcpAccept(const httplib::Request& request) {
  const std::string accept = request.get_header_value("Accept");
  return accept.find("application/json") != std::string::npos &&
         accept.find("text/event-stream") != std::string::npos;
}

bool ConstantTimeEqual(const std::string& left, const std::string& right) {
  std::size_t difference = left.size() ^ right.size();
  const std::size_t length = std::max(left.size(), right.size());
  for (std::size_t index = 0; index < length; ++index) {
    const unsigned char a = index < left.size() ? static_cast<unsigned char>(left[index]) : 0;
    const unsigned char b = index < right.size() ? static_cast<unsigned char>(right[index]) : 0;
    difference |= static_cast<std::size_t>(a ^ b);
  }
  return difference == 0;
}

}  // namespace

class DesktopHttpServer::Impl {
 public:
  const DesktopRouter* router = nullptr;
  const DesktopMcpServer* mcp_server = nullptr;
  httplib::Server server;
  std::thread server_thread;
  Config config;
  int bound_port = 0;
  bool running = false;

  bool IsAuthorizedControlRequest(const httplib::Request& request, httplib::Response& response) const {
    if (request.has_header("Origin") || !IsLoopbackHost(request.get_header_value("Host"))) {
      Json(response, 403, {{"success", false}, {"error", {{"code", "FORBIDDEN"},
          {"message", "Control requests must be a same-host local client request"}}}});
      return false;
    }
    const std::string expected = "Bearer " + config.control_token;
    if (request.get_header_value_count("Authorization") != 1 ||
        request.get_header_value("Authorization").size() > 1024 || config.control_token.empty() ||
        !ConstantTimeEqual(request.get_header_value("Authorization"), expected)) {
      Json(response, 401, {{"success", false}, {"error", {{"code", "UNAUTHORIZED"},
          {"message", "A local control capability is required"}}}});
      return false;
    }
    return true;
  }

  DesktopMcpServer::Config McpConfig() const {
    DesktopMcpServer::Config result;
    result.platform = PlatformFromString(config.platform).value_or(Platform::kLinux);
    result.engine = config.engine;
    result.server_name = config.server_name;
    result.server_version = config.server_version;
    return result;
  }
};

DesktopHttpServer::DesktopHttpServer() : impl_(std::make_unique<Impl>()) {}

DesktopHttpServer::~DesktopHttpServer() { Stop(); }

void DesktopHttpServer::SetRouter(const DesktopRouter* router) { impl_->router = router; }

void DesktopHttpServer::SetMcpServer(const DesktopMcpServer* server) { impl_->mcp_server = server; }

bool DesktopHttpServer::Start(const Config& config) {
  if (impl_->router == nullptr || impl_->mcp_server == nullptr || impl_->running ||
      config.control_token.empty() || !IsLoopbackHost(config.bind_host)) return false;
  impl_->config = config;
  impl_->server.set_payload_max_length(config.max_body_bytes);

  impl_->server.Get("/health", [](const httplib::Request&, httplib::Response& response) {
    Json(response, 200, {{"status", "ok"}});
  });
  impl_->server.Post("/v1/get-device-info", [this](const httplib::Request& request,
                                                     httplib::Response& response) {
    if (!HasJsonContentType(request)) {
      Json(response, 415, {{"success", false}, {"error", {{"code", "INVALID_CONTENT_TYPE"},
          {"message", "Discovery requests must use application/json"}}}});
      return;
    }
    const DesktopRouter::Result result = impl_->router->Dispatch("get-device-info", nlohmann::json::object());
    Json(response, result.status_code, result.body);
  });
  impl_->server.Get("/mcp", [](const httplib::Request&, httplib::Response& response) {
    response.status = 405;
    response.set_header("Allow", "POST");
  });
  impl_->server.Post("/mcp", [this](const httplib::Request& request, httplib::Response& response) {
    if (!impl_->IsAuthorizedControlRequest(request, response)) return;
    if (!HasJsonContentType(request) || !HasMcpAccept(request)) {
      Json(response, 406, {{"jsonrpc", "2.0"}, {"id", nullptr},
          {"error", {{"code", -32600}, {"message", "MCP requires JSON content and JSON/SSE accept types"}}}});
      return;
    }
    const std::string version = request.get_header_value("MCP-Protocol-Version");
    if (!version.empty() && version != kMcpProtocolVersion) {
      Json(response, 400, {{"jsonrpc", "2.0"}, {"id", nullptr},
          {"error", {{"code", -32600}, {"message", "Unsupported MCP-Protocol-Version"}}}});
      return;
    }
    nlohmann::json body;
    try { body = nlohmann::json::parse(request.body); } catch (...) {
      Json(response, 400, {{"jsonrpc", "2.0"}, {"id", nullptr},
          {"error", {{"code", -32700}, {"message", "Invalid JSON"}}}});
      return;
    }
    const nlohmann::json result = impl_->mcp_server->HandleRequest(body, impl_->McpConfig());
    if (result.is_null()) { response.status = 202; return; }
    Json(response, 200, result);
  });
  impl_->server.Post(R"(/v1/(.+))", [this](const httplib::Request& request,
                                            httplib::Response& response) {
    if (!impl_->IsAuthorizedControlRequest(request, response)) return;
    if (!HasJsonContentType(request)) {
      Json(response, 415, {{"success", false}, {"error", {{"code", "INVALID_CONTENT_TYPE"},
          {"message", "Control requests must use application/json"}}}});
      return;
    }
    nlohmann::json body = nlohmann::json::object();
    if (!request.body.empty()) {
      try { body = nlohmann::json::parse(request.body); } catch (...) {
        Json(response, 400, {{"success", false}, {"error", {{"code", "INVALID_JSON"},
            {"message", "Request body must be valid JSON"}}}});
        return;
      }
    }
    if (!body.is_object()) {
      Json(response, 400, {{"success", false}, {"error", {{"code", "INVALID_PARAMS"},
          {"message", "Request body must be a JSON object"}}}});
      return;
    }
    const DesktopRouter::Result result = impl_->router->Dispatch(request.matches[1].str(), body);
    Json(response, result.status_code, result.body);
  });

  impl_->server.set_read_timeout(config.read_timeout_seconds, 0);
  impl_->server.set_write_timeout(config.write_timeout_seconds, 0);
  if (config.port == 0) {
    impl_->bound_port = impl_->server.bind_to_any_port(config.bind_host.c_str());
    if (impl_->bound_port <= 0) return false;
  } else {
    if (!impl_->server.bind_to_port(config.bind_host.c_str(), config.port)) return false;
    impl_->bound_port = config.port;
  }
  impl_->running = true;
  impl_->server_thread = std::thread([this]() { impl_->server.listen_after_bind(); });
  return true;
}

void DesktopHttpServer::Stop() {
  if (!impl_->running) return;
  impl_->server.stop();
  if (impl_->server_thread.joinable()) impl_->server_thread.join();
  impl_->running = false;
  impl_->bound_port = 0;
}

bool DesktopHttpServer::IsRunning() const { return impl_->running; }
int DesktopHttpServer::bound_port() const { return impl_->bound_port; }

}  // namespace kelpie
