#include "kelpie/desktop_http_server.h"
#include "control_http_server.h"

#include <algorithm>
#include <atomic>
#include <mutex>
#include <optional>
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

void Draining(httplib::Response& response) {
  Json(response, 503, {{"success", false}, {"error", {{"code", "RUNTIME_SHUTTING_DOWN"},
      {"message", "The desktop runtime is shutting down"}}}});
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

}  // namespace

class DesktopHttpServer::Impl {
 public:
  const DesktopRouter* router = nullptr;
  const DesktopMcpServer* mcp_server = nullptr;
  ControlHttpServer server;
  std::thread server_thread;
  Config config;
  PeerApprovalQueue approvals;
  RequestHandler request_handler;
  explicit Impl(std::filesystem::path trust_path) : approvals(std::move(trust_path)) {}
  DesktopRouter::Result Dispatch(std::string_view method, const nlohmann::json& body) const {
    if (request_handler) {
      auto result = request_handler(method, body);
      return {result.first, std::move(result.second)};
    }
    return router->Dispatch(method, body);
  }
  int bound_port = 0;
  bool running = false;
  mutable std::mutex admission_mutex;
  bool accepting_requests = false;
  std::size_t active_requests = 0;
  std::atomic<bool> server_thread_finished = true;

  class RequestLease {
   public:
    explicit RequestLease(Impl* owner) : owner_(owner) {}
    RequestLease(const RequestLease&) = delete;
    RequestLease& operator=(const RequestLease&) = delete;
    RequestLease(RequestLease&& other) noexcept : owner_(other.owner_) { other.owner_ = nullptr; }
    RequestLease& operator=(RequestLease&& other) noexcept {
      if (this != &other) {
        Release();
        owner_ = other.owner_;
        other.owner_ = nullptr;
      }
      return *this;
    }
    ~RequestLease() { Release(); }

   private:
    void Release() {
      if (owner_ == nullptr) return;
      std::lock_guard<std::mutex> lock(owner_->admission_mutex);
      --owner_->active_requests;
      owner_ = nullptr;
    }
    Impl* owner_ = nullptr;
  };

  std::optional<RequestLease> AcquireRequest() {
    std::lock_guard<std::mutex> lock(admission_mutex);
    if (!accepting_requests) return std::nullopt;
    ++active_requests;
    return RequestLease(this);
  }

  void BeginDrain() {
    {
      std::lock_guard<std::mutex> lock(admission_mutex);
      if (!accepting_requests) return;
      accepting_requests = false;
    }
    // Start waits until listen_after_bind has entered its loop, so stop closes
    // the already-active listener without racing a late server startup.
    server.stop();
  }

  bool IsDrained() const {
    std::lock_guard<std::mutex> lock(admission_mutex);
    return active_requests == 0 && server_thread_finished.load();
  }

  bool IsSafeControlRequest(const httplib::Request& request, httplib::Response& response) const {
    const std::string site = request.get_header_value("Sec-Fetch-Site");
    if (request.has_header("Transfer-Encoding") || request.get_header_value_count("Authorization") > 1 ||
        request.get_header_value_count("Content-Length") > 1) {
      Json(response, 400, {{"success", false}, {"error", {{"code", "BAD_REQUEST"}, {"message", "Ambiguous control headers"}}}});
      return false;
    }
    if (request.has_header("Origin") || (!site.empty() && site != "none" && site != "same-origin") ||
        request.get_header_value_count("Host") != 1 || !IsSafeControlHost(request.get_header_value("Host"))) {
      Json(response, 403, {{"success", false}, {"error", {{"code", "FORBIDDEN"},
          {"message", "Browser requests cannot use computer approval"}}}});
      return false;
    }
    return true;
  }

  bool IsAuthorizedControlRequest(const httplib::Request& request, httplib::Response& response) const {
    if (!IsSafeControlRequest(request, response)) return false;
    if (!approvals.Authorize(request.remote_addr, request.get_header_value("Authorization").rfind("Bearer ", 0) == 0
        ? request.get_header_value("Authorization").substr(7) : std::string())) {
      Json(response, 401, {{"success", false}, {"error", {{"code", "UNAUTHORIZED"},
          {"message", "Approve this computer on Kelpie"}}}});
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

DesktopHttpServer::DesktopHttpServer(std::filesystem::path trust_path) : impl_(std::make_unique<Impl>(std::move(trust_path))) {}

DesktopHttpServer::~DesktopHttpServer() { Stop(); }

void DesktopHttpServer::SetRouter(const DesktopRouter* router) { impl_->router = router; }

void DesktopHttpServer::SetMcpServer(const DesktopMcpServer* server) { impl_->mcp_server = server; }
void DesktopHttpServer::SetRequestHandler(RequestHandler handler) { impl_->request_handler = std::move(handler); }

bool DesktopHttpServer::Start(const Config& config) {
  if (((impl_->router == nullptr || impl_->mcp_server == nullptr) && !impl_->request_handler) || impl_->running ||
      (!CanonicalPeerAddress(config.bind_host) && config.bind_host != "localhost")) return false;
  impl_->config = config;
  impl_->approvals.SetAvailable(config.approval_available);
  impl_->server.request_read_budget = std::chrono::seconds(config.read_timeout_seconds);
  impl_->server.new_task_queue = [] { return new httplib::ThreadPool(8, 32); };
  impl_->server.set_exception_handler([](const httplib::Request&, httplib::Response& response, std::exception_ptr) {
    Json(response, 500, {{"success", false}, {"error", {{"code", "INTERNAL_ERROR"}, {"message", "Request could not be completed"}}}});
  });
  {
    std::lock_guard<std::mutex> lock(impl_->admission_mutex);
    impl_->accepting_requests = true;
    impl_->active_requests = 0;
  }
  impl_->server.set_payload_max_length(config.max_body_bytes);

  impl_->server.Get("/health", [](const httplib::Request&, httplib::Response& response) {
    Json(response, 200, {{"status", "ok"}});
  });
  auto discovery = [this](const httplib::Request& request, httplib::Response& response) {
    auto lease = impl_->AcquireRequest();
    if (!lease) { Draining(response); return; }
    auto result = impl_->Dispatch("get-device-info", nlohmann::json::object());
    result.body["approvalMode"] = "computer-key";
    result.body["localhostTrusted"] = true;
    result.body["requiresPairing"] = !IsLoopbackPeer(request.remote_addr);
    Json(response, result.status_code, result.body);
  };
  impl_->server.Post("/v1/get-device-info", discovery);
  impl_->server.Get("/v1/get-device-info", discovery);
  impl_->server.Post("/v1/pair", [this](const httplib::Request& request, httplib::Response& response) {
    auto lease = impl_->AcquireRequest();
    if (!lease) { Draining(response); return; }
    if (!impl_->IsSafeControlRequest(request, response)) return;
    response.set_header("Cache-Control", "no-store");
    if (!HasJsonContentType(request)) {
      Json(response, 415, {{"success", false}, {"error", {{"code", "UNSUPPORTED_MEDIA_TYPE"}, {"message", "JSON is required"}}}});
      return;
    }
    try {
      const auto result = impl_->approvals.Start(request.remote_addr, nlohmann::json::parse(request.body));
      Json(response, result.status, result.body);
    } catch (...) { Json(response, 400, {{"success", false}, {"error", {{"code", "INVALID_JSON"}, {"message", "Invalid pair request"}}}}); }
  });
  impl_->server.Get("/v1/pair/status", [this](const httplib::Request& request, httplib::Response& response) {
    auto lease = impl_->AcquireRequest();
    if (!lease) { Draining(response); return; }
    if (!impl_->IsSafeControlRequest(request, response)) return;
    response.set_header("Cache-Control", "no-store");
    Json(response, 200, impl_->approvals.Status(request.remote_addr, request.get_param_value("requestId")));
  });
  impl_->server.Delete("/v1/pair", [this](const httplib::Request& request, httplib::Response& response) {
    auto lease = impl_->AcquireRequest();
    if (!lease) { Draining(response); return; }
    if (!impl_->IsAuthorizedControlRequest(request, response)) return;
    try {
      const auto header = request.get_header_value("Authorization");
      const auto key = impl_->approvals.store().Authorize(header.rfind("Bearer ", 0) == 0 ? header.substr(7) : "");
      if (!key) { Json(response, 400, {{"success", false}}); return; }
      impl_->approvals.store().Revoke(*key); Json(response, 200, {{"success", true}});
    }
    catch (...) { Json(response, 500, {{"success", false}, {"error", {{"code", "STORAGE_ERROR"}, {"message", "Could not revoke computer"}}}}); }
  });
  if (config.debug_page) impl_->server.Get("/debug/coordinate-calibration", [this](const httplib::Request& request, httplib::Response& response) {
    auto lease = impl_->AcquireRequest();
    if (!lease) { Draining(response); return; }
    if (!impl_->IsAuthorizedControlRequest(request, response)) return;
    const auto page = impl_->config.debug_page();
    if (page.empty()) { Json(response, 404, {{"success", false}}); return; }
    response.set_content(page, "text/html; charset=utf-8");
  });
  impl_->server.Options(R"(/.*)", [](const httplib::Request&, httplib::Response& response) {
    response.set_header("Allow", "POST");
    Json(response, 405, {{"success", false}, {"error", {{"code", "METHOD_NOT_ALLOWED"}, {"message", "Browser preflight is not permitted"}}}});
  });
  impl_->server.Get("/mcp", [](const httplib::Request&, httplib::Response& response) {
    response.status = 405;
    response.set_header("Allow", "POST");
  });
  impl_->server.Post("/mcp", [this](const httplib::Request& request, httplib::Response& response) {
    auto lease = impl_->AcquireRequest();
    if (!lease) { Draining(response); return; }
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
    auto result = impl_->request_handler ? impl_->request_handler("mcp", body)
        : std::make_pair(200, impl_->mcp_server->HandleRequest(body, impl_->McpConfig()));
    if (result.second.is_null()) { response.status = 202; return; }
    Json(response, result.first, result.second);
  });
  impl_->server.Post(R"(/v1/(.+))", [this](const httplib::Request& request,
                                            httplib::Response& response) {
    auto lease = impl_->AcquireRequest();
    if (!lease) { Draining(response); return; }
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
    const DesktopRouter::Result result = impl_->Dispatch(request.matches[1].str(), body);
    Json(response, result.status_code, result.body);
  });

  impl_->server.set_read_timeout(config.read_timeout_seconds, 0);
  impl_->server.set_write_timeout(config.write_timeout_seconds, 0);
  bool ipv6 = false;
  bool socket_option_failed = false;
  impl_->server.set_ipv6_v6only(false);
  impl_->server.set_socket_options([&](socket_t socket) {
    httplib::default_socket_options(socket);
    if (ipv6) {
      const int disabled = 0;
      socket_option_failed = setsockopt(socket, IPPROTO_IPV6, IPV6_V6ONLY,
          reinterpret_cast<const char*>(&disabled), sizeof(disabled)) != 0;
    }
  });
  const auto bind = [&](const std::string& host) {
    ipv6 = host == "::";
    socket_option_failed = false;
    const int port = config.port == 0 ? impl_->server.bind_to_any_port(host.c_str())
        : (impl_->server.bind_to_port(host.c_str(), config.port) ? config.port : -1);
    if (socket_option_failed && port > 0) { impl_->server.CloseUnstartedListener(); return -1; }
    return port;
  };
  impl_->bound_port = bind(config.bind_host);
  if (impl_->bound_port <= 0 && config.bind_host == "::") impl_->bound_port = bind("0.0.0.0");
  // Socket options are needed only during bind; never retain stack references.
  impl_->server.set_socket_options(httplib::default_socket_options);
  if (impl_->bound_port <= 0) return false;
  impl_->server_thread_finished.store(false);
  impl_->server_thread = std::thread([this]() {
    impl_->server.listen_after_bind();
    impl_->server_thread_finished.store(true);
  });
  // Do not report a started runtime until the listener has entered its loop.
  // BeginDrain can then safely close the bound socket without a startup race.
  impl_->server.wait_until_ready();
  if (!impl_->server.is_running()) {
    if (impl_->server_thread.joinable()) impl_->server_thread.join();
    std::lock_guard<std::mutex> lock(impl_->admission_mutex);
    impl_->accepting_requests = false;
    impl_->bound_port = 0;
    return false;
  }
  impl_->running = true;
  return true;
}

void DesktopHttpServer::BeginDrain() {
  if (!impl_->running) return;
  impl_->BeginDrain();
}

bool DesktopHttpServer::IsDrained() const {
  return !impl_->running || impl_->IsDrained();
}

void DesktopHttpServer::Stop() {
  if (!impl_->running) return;
  impl_->BeginDrain();
  if (impl_->server_thread.joinable()) impl_->server_thread.join();
  impl_->running = false;
  impl_->bound_port = 0;
}
bool DesktopHttpServer::IsRunning() const { return impl_->running; }
int DesktopHttpServer::bound_port() const { return impl_->bound_port; }
PeerApprovalQueue& DesktopHttpServer::approvals() { return impl_->approvals; }

}  // namespace kelpie
