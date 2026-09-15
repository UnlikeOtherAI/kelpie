#include "kelpie/desktop_mcp_server.h"

#include <algorithm>
#include <iostream>
#include <string_view>

#include "kelpie/desktop_router.h"
#include "kelpie/mcp_registry.h"
#include "kelpie/response_helpers.h"

namespace kelpie {
namespace {

constexpr std::string_view kProtocolVersion = "2025-06-18";

nlohmann::json JsonRpcResult(const nlohmann::json& id, const nlohmann::json& result) {
  return {{"jsonrpc", "2.0"}, {"id", id}, {"result", result}};
}

nlohmann::json JsonRpcError(const nlohmann::json& id, int code, const std::string& message) {
  return {{"jsonrpc", "2.0"},
          {"id", id},
          {"error", {{"code", code}, {"message", message}}}};
}

bool IsJsonRpcRequest(const nlohmann::json& request) {
  if (!request.is_object()) {
    return false;
  }
  const auto jsonrpc = request.find("jsonrpc");
  const auto method = request.find("method");
  return jsonrpc != request.end() && jsonrpc->is_string() && *jsonrpc == "2.0" &&
         method != request.end() && method->is_string();
}

bool IsNotification(const nlohmann::json& request) {
  return IsJsonRpcRequest(request) && !request.contains("id");
}

nlohmann::json ReplyOrNothing(bool notification, nlohmann::json response) {
  return notification ? nlohmann::json(nullptr) : std::move(response);
}

nlohmann::json InputSchema(std::string_view endpoint) {
  nlohmann::json properties = {
      {"tabId", {{"type", "string"}}},
      {"generation", {{"type", "integer"}, {"minimum", 0}}},
  };
  nlohmann::json required = nlohmann::json::array();
  if (endpoint == "navigate") {
    properties["url"] = {{"type", "string"}, {"minLength", 1}};
    required.push_back("url");
  } else if (endpoint == "evaluate") {
    properties["expression"] = {{"type", "string"}, {"minLength", 1}};
    required.push_back("expression");
  } else if (endpoint == "new-tab") {
    properties["url"] = {{"type", "string"}, {"minLength", 1}};
  } else if (endpoint == "click") {
    properties["selector"] = {{"type", "string"}, {"minLength", 1}};
    required.push_back("selector");
  } else if (endpoint == "fill") {
    properties["selector"] = {{"type", "string"}, {"minLength", 1}};
    properties["value"] = {{"type", "string"}};
    required = {"selector", "value"};
  } else if (endpoint == "type") {
    properties["text"] = {{"type", "string"}};
    required.push_back("text");
  } else if (endpoint == "press-key") {
    properties["key"] = {{"type", "string"}, {"minLength", 1}};
    properties["code"] = {{"type", "string"}};
    properties["modifiers"] = {{"type", "array"}, {"items", {{"type", "string"}}}};
    required.push_back("key");
  } else if (endpoint == "set-home") {
    properties["url"] = {{"type", "string"}, {"minLength", 1}};
    required.push_back("url");
  } else if (endpoint == "toast") {
    properties["message"] = {{"type", "string"}, {"minLength", 1}};
    required.push_back("message");
  } else if (endpoint == "set-fullscreen") {
    properties["enabled"] = {{"type", "boolean"}};
    required.push_back("enabled");
  } else if (endpoint == "handle-dialog") {
    properties["action"] = {{"enum", {"accept", "dismiss"}}};
    properties["promptText"] = {{"type", "string"}};
    required.push_back("action");
  } else if (endpoint == "scroll") {
    properties["deltaX"] = {{"type", "number"}};
    properties["deltaY"] = {{"type", "number"}};
  } else if (endpoint == "screenshot" || endpoint == "screenshot-annotated") {
    properties["format"] = {{"enum", {"png", "jpeg"}}};
    properties["fullPage"] = {{"type", "boolean"}};
  }
  return {{"type", "object"},
          {"properties", std::move(properties)},
          {"required", std::move(required)},
          {"additionalProperties", true}};
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
    const json response = HandleRequest(request, config);
    if (!response.is_null()) {
      output << response.dump() << '\n';
      output.flush();
    }
  }
  return true;
}

DesktopMcpServer::json DesktopMcpServer::HandleRequest(const json& request,
                                                       const Config& config) const {
  if (!IsJsonRpcRequest(request)) {
    return JsonRpcError(nullptr, -32600, "Request must be a JSON-RPC 2.0 object with a method");
  }
  const bool notification = IsNotification(request);
  if (request.contains("id") && !request["id"].is_null() &&
      !request["id"].is_string() && !request["id"].is_number()) {
    return JsonRpcError(nullptr, -32600, "id must be a string, number, or null");
  }
  const nlohmann::json id = notification ? nlohmann::json(nullptr) : request.value("id", nlohmann::json(nullptr));
  const std::string method = request["method"].get<std::string>();
  if (method.empty()) {
    return ReplyOrNothing(notification, JsonRpcError(id, -32600, "method is required"));
  }
  if (impl_->registry == nullptr) {
    return ReplyOrNothing(notification, JsonRpcError(id, -32000, "MCP registry is not configured"));
  }
  if (method == "initialize") {
    const nlohmann::json params = request.contains("params") ? request["params"] : nlohmann::json::object();
    if (!params.is_object()) {
      return ReplyOrNothing(notification, JsonRpcError(id, -32602, "initialize.params must be an object"));
    }
    if (params.contains("protocolVersion") && !params["protocolVersion"].is_string()) {
      return ReplyOrNothing(notification, JsonRpcError(id, -32602, "initialize.protocolVersion must be a string"));
    }
    // The transport is stateless, so return the version this server actually
    // speaks.  A client offering a newer version can use this result to retry
    // subsequent requests with the negotiated header value.
    return ReplyOrNothing(notification, JsonRpcResult(id,
                         {{"protocolVersion", kProtocolVersion},
                          {"serverInfo", {{"name", config.server_name},
                                          {"version", config.server_version}}},
                          {"capabilities", {{"tools", nlohmann::json::object()}}}}));
  }

  if (method == "notifications/initialized") {
    return ReplyOrNothing(notification, JsonRpcResult(id, nlohmann::json::object()));
  }

  if (method == "ping") {
    return ReplyOrNothing(notification, JsonRpcResult(id, nlohmann::json::object()));
  }

  if (method == "tools/list") {
    nlohmann::json tools = nlohmann::json::array();
    for (const McpTool& tool : impl_->registry->all_tools()) {
      if (!SupportsPlatform(tool.availability, config.platform) ||
          !SupportsEngine(tool.availability, config.engine) || impl_->router == nullptr ||
          !impl_->router->IsCallable(tool.http_endpoint)) {
        continue;
      }
      tools.push_back({{"name", tool.name},
                       {"description", tool.description},
                       {"inputSchema", InputSchema(tool.http_endpoint)}});
    }
    return ReplyOrNothing(notification, JsonRpcResult(id, {{"tools", tools}}));
  }

  if (method == "tools/call") {
    if (impl_->router == nullptr) {
      return JsonRpcError(id, -32000, "Desktop router is not configured");
    }
    const nlohmann::json params = request.contains("params") ? request["params"] : nlohmann::json::object();
    if (!params.is_object()) {
      return ReplyOrNothing(notification, JsonRpcError(id, -32602, "tools/call.params must be an object"));
    }
    if (!params.contains("name") || !params["name"].is_string() || params["name"].empty()) {
      return ReplyOrNothing(notification, JsonRpcError(id, -32602, "params.name is required"));
    }
    const std::string tool_name = params["name"].get<std::string>();

    const auto match = std::find_if(impl_->registry->all_tools().begin(),
                                    impl_->registry->all_tools().end(),
                                    [&](const McpTool& tool) { return tool.name == tool_name; });
    if (match == impl_->registry->all_tools().end()) {
      return ReplyOrNothing(notification, JsonRpcError(id, -32602, "Unknown tool: " + tool_name));
    }
    if (!SupportsPlatform(match->availability, config.platform) ||
        !SupportsEngine(match->availability, config.engine) ||
        !impl_->router->IsCallable(match->http_endpoint)) {
      return ReplyOrNothing(notification, JsonRpcError(id, -32601, "Tool is not available in this runtime"));
    }

    const nlohmann::json arguments = params.contains("arguments") ? params["arguments"] : nlohmann::json::object();
    if (!arguments.is_object()) {
      return ReplyOrNothing(notification, JsonRpcError(id, -32602, "tools/call.arguments must be an object"));
    }

    const DesktopRouter::Result result =
        impl_->router->Dispatch(match->http_endpoint, arguments);
    json content = {{{"type", "text"}, {"text", result.body.dump()}}};
    if ((match->http_endpoint == "screenshot" || match->http_endpoint == "screenshot-annotated") &&
        result.body.value("success", false) && result.body.contains("image") &&
        result.body["image"].is_string()) {
      const std::string format = result.body.value("format", std::string("png"));
      content.push_back({{"type", "image"}, {"data", result.body["image"]},
                         {"mimeType", "image/" + format}});
    }
    const json response = JsonRpcResult(id, {{"content", content},
                                               {"structuredContent", result.body},
                                               {"isError", !result.body.value("success", false)}});
    return ReplyOrNothing(notification, response);
  }

  const json response = JsonRpcError(id, -32601, "Unsupported method: " + method);
  return ReplyOrNothing(notification, response);
}

}  // namespace kelpie
