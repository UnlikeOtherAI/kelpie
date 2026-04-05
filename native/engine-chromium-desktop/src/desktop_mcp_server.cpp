#include "kelpie/desktop_mcp_server.h"

#include <algorithm>
#include <iostream>

#include "kelpie/desktop_router.h"
#include "kelpie/mcp_registry.h"
#include "kelpie/response_helpers.h"

namespace kelpie {
namespace {

nlohmann::json JsonRpcResult(const nlohmann::json& id, const nlohmann::json& result) {
  return {{"jsonrpc", "2.0"}, {"id", id}, {"result", result}};
}

nlohmann::json JsonRpcError(const nlohmann::json& id, int code, const std::string& message) {
  return {{"jsonrpc", "2.0"},
          {"id", id},
          {"error", {{"code", code}, {"message", message}}}};
}

}  // namespace

class DesktopMcpServer::Impl {
 public:
  const DesktopRouter* router = nullptr;
  const McpRegistry* registry = nullptr;
};

DesktopMcpServer::DesktopMcpServer() : impl_(std::make_unique<Impl>()) {}

DesktopMcpServer::~DesktopMcpServer() = default;

void DesktopMcpServer::SetRouter(const DesktopRouter* router) {
  impl_->router = router;
}

void DesktopMcpServer::SetRegistry(const McpRegistry* registry) {
  impl_->registry = registry;
}

bool DesktopMcpServer::Run(const Config& config) {
  std::istream& input = config.input != nullptr ? *config.input : std::cin;
  std::ostream& output = config.output != nullptr ? *config.output : std::cout;

  std::string line;
  while (std::getline(input, line)) {
    if (line.empty()) {
      continue;
    }
    nlohmann::json request;
    try {
      request = nlohmann::json::parse(line);
    } catch (...) {
      output << JsonRpcError(nullptr, -32700, "Invalid JSON") << '\n';
      output.flush();
      continue;
    }
    output << HandleRequest(request, config).dump() << '\n';
    output.flush();
  }
  return true;
}

DesktopMcpServer::json DesktopMcpServer::HandleRequest(const json& request,
                                                       const Config& config) const {
  const nlohmann::json id = request.contains("id") ? request["id"] : nlohmann::json(nullptr);
  const std::string method = request.value("method", std::string());
  if (method.empty()) {
    return JsonRpcError(id, -32600, "method is required");
  }
  if (impl_->registry == nullptr) {
    return JsonRpcError(id, -32000, "MCP registry is not configured");
  }
  if (method == "initialize") {
    return JsonRpcResult(id,
                         {{"protocolVersion", "2024-11-05"},
                          {"serverInfo", {{"name", config.server_name},
                                          {"version", config.server_version}}},
                          {"capabilities", {{"tools", nlohmann::json::object()}}}});
  }

  if (method == "tools/list") {
    nlohmann::json tools = nlohmann::json::array();
    for (const McpTool& tool : impl_->registry->all_tools()) {
      if (!SupportsPlatform(tool.availability, config.platform) ||
          !SupportsEngine(tool.availability, config.engine)) {
        continue;
      }
      tools.push_back({{"name", tool.name},
                       {"description", tool.description},
                       {"inputSchema",
                        {{"type", "object"}, {"additionalProperties", true}}}});
    }
    return JsonRpcResult(id, {{"tools", tools}});
  }

  if (method == "tools/call") {
    if (impl_->router == nullptr) {
      return JsonRpcError(id, -32000, "Desktop router is not configured");
    }
    const nlohmann::json params = request.value("params", nlohmann::json::object());
    const std::string tool_name = params.value("name", std::string());
    if (tool_name.empty()) {
      return JsonRpcError(id, -32602, "params.name is required");
    }

    const auto match = std::find_if(impl_->registry->all_tools().begin(),
                                    impl_->registry->all_tools().end(),
                                    [&](const McpTool& tool) { return tool.name == tool_name; });
    if (match == impl_->registry->all_tools().end()) {
      return JsonRpcError(id, -32602, "Unknown tool: " + tool_name);
    }
    if (!SupportsPlatform(match->availability, config.platform) ||
        !SupportsEngine(match->availability, config.engine)) {
      return JsonRpcError(id, -32601, "Tool is not available in this runtime");
    }

    const DesktopRouter::Result result =
        impl_->router->Dispatch(match->http_endpoint, params.value("arguments", nlohmann::json::object()));
    return JsonRpcResult(id,
                         {{"content", {{{"type", "text"}, {"text", result.body.dump()}}}},
                          {"structuredContent", result.body},
                          {"isError", !result.body.value("success", false)}});
  }

  return JsonRpcError(id, -32601, "Unsupported method: " + method);
}

}  // namespace kelpie
