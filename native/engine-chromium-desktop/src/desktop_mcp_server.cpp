#include "kelpie/desktop_mcp_server.h"
#include "kelpie/browser_gateway.h"
#include "kelpie/desktop_router.h"
#include "kelpie/mcp_registry.h"
#include "kelpie/native_extension_schema.h"
#include <iostream>
#include <atomic>
#include <mutex>
namespace kelpie {
namespace {
using json = nlohmann::json;
json RpcError(int code) {
  return {{"jsonrpc", "2.0"}, {"id", nullptr}, {"error", {{"code", code}, {"message", "Invalid MCP request"}}}};
}
}
class DesktopMcpServer::Impl {
 public:
  const DesktopRouter* router = nullptr;
  const McpRegistry* registry = nullptr;
  FixedReader reader;
  mutable std::recursive_mutex mutex;
  mutable std::unique_ptr<BrowserGateway> gateway;
  mutable bool internal_dispatch = false;
  mutable std::atomic<bool> document_changed{false};
  void DrainDocuments() const { if (gateway && document_changed.exchange(false)) gateway->InvalidateReferences(); }
  void Ensure(const Config& config) const {
    if (gateway) return;
    json methods = json::array(), extensions = json::array();
    if (router) for (const auto& method : router->RegisteredMethods()) if (router->IsCallable(method)) methods.push_back(method);
    if (registry && router) for (const auto& tool : registry->all_tools()) {
      if (!SupportsPlatform(tool.availability, config.platform) || !SupportsEngine(tool.availability, config.engine) || !router->IsCallable(tool.http_endpoint)) continue;
      extensions.push_back({{"name", tool.name}, {"method", tool.http_endpoint}, {"description", tool.description},
        {"inputSchema", NativeExtensionInputSchema(tool.http_endpoint)}, {"mutates", NativeExtensionMutates(tool.http_endpoint)}});
    }
    gateway = std::make_unique<BrowserGateway>(json{{"nativeMethods", methods}, {"fixedReader", static_cast<bool>(reader)},
      {"requireAuthorization", false}, {"extensions", extensions}});
  }
  json Run(json step) const {
    while (step.value("kind", std::string()) != "complete") {
      if (step.value("kind", std::string()) == "authorize") { step = gateway->Advance({{"success", true}}); continue; }
      json result;
      try {
        DrainDocuments();
        const std::string method = step.at("method");
        internal_dispatch = true;
        if (method == "browser-control-evaluate" && reader) result = reader(step.at("params"));
        else if (router) result = router->Dispatch(method, step.at("params")).body;
        else result = {{"success", false}};
        internal_dispatch = false;
        step = gateway->Advance(std::move(result));
        DrainDocuments();
      } catch (...) { internal_dispatch = false; step = gateway->Cancel(); }
    }
    return step["response"];
  }
};
DesktopMcpServer::DesktopMcpServer() : impl_(std::make_unique<Impl>()) {}
DesktopMcpServer::~DesktopMcpServer() = default;
void DesktopMcpServer::SetRouter(const DesktopRouter* router) { impl_->router = router; impl_->gateway.reset(); }
void DesktopMcpServer::SetRegistry(const McpRegistry* registry) { impl_->registry = registry; impl_->gateway.reset(); }
void DesktopMcpServer::SetFixedReader(FixedReader reader) { impl_->reader = std::move(reader); impl_->gateway.reset(); }
void DesktopMcpServer::NotifyDocumentChanged() const { impl_->document_changed.store(true); }
std::shared_ptr<void> DesktopMcpServer::GuardDispatch(std::string_view method, const json& params) const {
  auto lock = std::make_shared<std::unique_lock<std::recursive_mutex>>(impl_->mutex);
  InvalidateReferences(method, params);
  return lock;
}
void DesktopMcpServer::InvalidateReferences(std::string_view method, const json& params) const {
  std::lock_guard<std::recursive_mutex> lock(impl_->mutex);
  if (!impl_->gateway || impl_->internal_dispatch || method == "browser-control" || !NativeExtensionMutates(method)) return;
  impl_->gateway->InvalidateReferences(params.contains("tabId") && params["tabId"].is_string() ? params["tabId"].get<std::string>() : "");
}
bool DesktopMcpServer::Run(const Config& config) {
  std::istream& input = config.input ? *config.input : std::cin;
  std::ostream& output = config.output ? *config.output : std::cout;
  std::string line;
  while (std::getline(input, line)) {
    if (line.empty()) continue;
    json request = json::parse(line, nullptr, false);
    const json response = request.is_discarded() ? RpcError(-32700) : HandleRequest(request, config);
    if (!response.is_null()) { output << response.dump() << '\n'; output.flush(); }
  }
  return true;
}
DesktopMcpServer::json DesktopMcpServer::HandleRequest(const json& request, const Config& config) const {
  std::lock_guard<std::recursive_mutex> lock(impl_->mutex);
  impl_->Ensure(config);
  impl_->DrainDocuments();
  try { return impl_->Run(impl_->gateway->BeginMcp(request)); } catch (...) { return RpcError(-32600); }
}
DesktopMcpServer::json DesktopMcpServer::HandleBrowserRequest(const json& request, const Config& config) const {
  std::lock_guard<std::recursive_mutex> lock(impl_->mutex);
  impl_->Ensure(config);
  impl_->DrainDocuments();
  return impl_->Run(impl_->gateway->Begin(request));
}
}
