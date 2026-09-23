#include "kelpie/desktop_mcp_server.h"

#include <algorithm>
#include <cstdint>
#include <iostream>
#include <optional>
#include <string_view>

#include "desktop_mcp_page_text.h"
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
  nlohmann::json properties = nlohmann::json::object();
  nlohmann::json required = nlohmann::json::array();
  const auto string = [&properties](const char* name, bool required_field = false) {
    properties[name] = {{"type", "string"}, {"minLength", required_field ? 1 : 0}};
  };
  const auto integer = [&properties](const char* name, int minimum = 0) {
    properties[name] = {{"type", "integer"}, {"minimum", minimum}};
  };
  const auto number = [&properties](const char* name) {
    properties[name] = {{"type", "number"}};
  };
  const auto tab_scoped = [&properties] {
    properties["tabId"] = {{"type", "string"}, {"minLength", 1}};
    properties["generation"] = {{"type", "integer"}, {"minimum", 0}};
    properties["timeout"] = {{"type", "integer"}, {"minimum", 1}, {"maximum", 30000}};
  };
  const auto require = [&required](const char* name) { required.push_back(name); };
  const bool scoped = endpoint == "navigate" || endpoint == "back" || endpoint == "forward" ||
      endpoint == "reload" || endpoint == "get-current-url" ||
      endpoint == "switch-tab" || endpoint == "close-tab" || endpoint == "get-dom" ||
      endpoint == "query-selector" || endpoint == "query-selector-all" ||
      endpoint == "get-element-text" || endpoint == "get-attributes" || endpoint == "evaluate" ||
      endpoint == "wait-for-element" || endpoint == "wait-for-navigation" || endpoint == "click" ||
      endpoint == "fill" || endpoint == "type" || endpoint == "select-option" || endpoint == "check" ||
      endpoint == "uncheck" || endpoint == "press-key" || endpoint == "scroll" ||
      endpoint == "scroll-to-top" || endpoint == "scroll-to-bottom" || endpoint == "screenshot" ||
      endpoint == "screenshot-annotated" || endpoint == "get-cookies" || endpoint == "set-cookie" ||
      endpoint == "delete-cookies" || endpoint == "clear-cookies" || endpoint == "get-storage" ||
      endpoint == "set-storage" || endpoint == "clear-storage" || endpoint == "get-dialog" ||
      endpoint == "handle-dialog" || endpoint == "find-element" || endpoint == "find-button" ||
      endpoint == "find-link" || endpoint == "find-input" || endpoint == "get-page-text" ||
      endpoint == "get-visible-elements" || endpoint == "get-form-state" || endpoint == "get-accessibility-tree";
  if (scoped) tab_scoped();

  if (endpoint == "navigate" || endpoint == "set-home") { string("url", true); require("url"); }
  else if (endpoint == "new-tab") { string("url", true); properties["timeout"] = {{"type", "integer"}, {"minimum", 1}, {"maximum", 30000}}; }
  else if (endpoint == "evaluate") { string("expression", true); require("expression"); }
  else if (endpoint == "query-selector" || endpoint == "query-selector-all" || endpoint == "get-element-text" || endpoint == "get-attributes") { string("selector", true); require("selector"); }
  else if (endpoint == "get-dom") string("selector");
  else if (endpoint == "wait-for-element") {
    string("selector", true);
    properties["state"] = {{"enum", {"attached", "visible", "hidden"}}};
    require("selector");
  }
  else if (endpoint == "click" || endpoint == "check" || endpoint == "uncheck") { string("selector", true); require("selector"); }
  else if (endpoint == "fill" || endpoint == "select-option") { string("selector", true); string("value"); require("selector"); require("value"); }
  else if (endpoint == "type") { string("text", true); string("selector"); require("text"); }
  else if (endpoint == "press-key") {
    string("key", true); string("code");
    properties["modifiers"] = {{"type", "array"}, {"items", {{"type", "string"},
        {"enum", {"Alt", "Control", "Meta", "Shift"}}}}};
    require("key");
  }
  else if (endpoint == "scroll") {
    number("deltaX");
    number("deltaY");
    require("deltaX"); require("deltaY");
  }
  else if (endpoint == "screenshot" || endpoint == "screenshot-annotated") {
    properties["format"] = {{"enum", {"png", "jpeg"}}};
    integer("quality", 1); properties["quality"]["maximum"] = 100;
    integer("maxWidth", 1); properties["maxWidth"]["maximum"] = 16384;
  }
  else if (endpoint == "get-cookies") { string("url"); string("name"); }
  else if (endpoint == "set-cookie") {
    string("name", true); string("value"); string("url"); string("domain"); string("path");
    string("expires"); properties["httpOnly"] = {{"type", "boolean"}};
    properties["secure"] = {{"type", "boolean"}};
    properties["sameSite"] = {{"enum", {"Strict", "Lax", "None", "strict", "lax", "none"}}};
    require("name"); require("value");
  } else if (endpoint == "delete-cookies") {
    string("name"); string("domain"); properties["deleteAll"]={{"type","boolean"}};
  }
  else if (endpoint == "get-storage") { properties["type"]={{"enum",{"local","session"}}}; string("key"); }
  else if (endpoint == "set-storage") { properties["type"]={{"enum",{"local","session"}}}; string("key",true); string("value"); require("key"); require("value"); }
  else if (endpoint == "clear-storage") properties["type"]={{"enum",{"local","session","both"}}};
  else if (endpoint == "handle-dialog") { properties["action"]={{"enum",{"accept","dismiss"}}}; string("promptText"); require("action"); }
  else if (endpoint == "find-element") {
    string("text", true); string("role"); string("selector"); require("text");
  } else if (endpoint == "find-button" || endpoint == "find-link") {
    string("text", true); require("text");
  } else if (endpoint == "find-input") {
    string("label"); string("placeholder"); string("name");
  } else if (endpoint == "get-page-text") {
    properties["mode"] = {{"enum", {"readable", "full", "markdown"}}}; string("selector");
    integer("maxChars", 1);  // Applied here, never sent to the handler.
  } else if (endpoint == "get-visible-elements") {
    properties["interactableOnly"] = {{"type", "boolean"}};
    properties["includeText"] = {{"type", "boolean"}};
  } else if (endpoint == "get-form-state") {
    string("selector");
  } else if (endpoint == "get-accessibility-tree") {
    string("root"); properties["interactableOnly"] = {{"type", "boolean"}};
    integer("maxDepth", 0);
    properties["maxDepth"]["maximum"] = 100;
  }
  else if (endpoint == "toast") { string("message", true); require("message"); }
  else if (endpoint == "set-fullscreen") { properties["enabled"]={{"type","boolean"}}; require("enabled"); }
  else if (endpoint == "resize-viewport") {
    integer("width", 1); integer("height", 1);
    properties["width"]["maximum"] = 16384; properties["height"]["maximum"] = 16384;
    require("width"); require("height");
  }
  else if (endpoint == "bookmarks-add") { string("url",true); string("title"); require("url"); }
  else if (endpoint == "bookmarks-remove") { string("id",true); require("id"); }
  else if (endpoint == "history-list" || endpoint == "get-history") integer("limit",1);
  else if (endpoint == "get-tabs") {
    properties["timeout"] = {{"type", "integer"}, {"minimum", 1}, {"maximum", 30000}};
  } else if (endpoint == "get-console-messages") {
    properties["level"] = {{"enum", {"log", "warn", "error", "info", "debug"}}};
    string("since"); integer("limit", 1);
  } else if (endpoint == "get-network-log") {
    string("type"); string("since");
    properties["status"] = {{"enum", {"success", "error", "pending"}}};
    integer("limit", 1);
  }
  return {{"type", "object"}, {"properties", std::move(properties)}, {"required", std::move(required)}, {"additionalProperties", false}};
}

std::optional<std::string> ValidateToolArguments(const nlohmann::json& schema,
                                                 const nlohmann::json& arguments) {
  const auto& properties = schema.at("properties");
  for (const auto& required : schema.at("required")) {
    const std::string name = required.get<std::string>();
    if (!arguments.contains(name)) return name + " is required";
  }
  for (auto it = arguments.begin(); it != arguments.end(); ++it) {
    if (!properties.contains(it.key())) return "Unknown argument: " + it.key();
    const auto& property = properties.at(it.key());
    if (property.contains("const") && it.value() != property.at("const")) {
      return it.key() + " must equal " + property.at("const").dump();
    }
    if (property.contains("enum") &&
        std::find(property.at("enum").begin(), property.at("enum").end(), it.value()) ==
            property.at("enum").end()) return it.key() + " has an invalid value";
    const std::string type = property.value("type", std::string());
    const bool type_ok = type.empty() ||
        (type == "string" && it.value().is_string()) ||
        (type == "integer" && it.value().is_number_integer()) ||
        (type == "number" && it.value().is_number()) ||
        (type == "boolean" && it.value().is_boolean()) ||
        (type == "array" && it.value().is_array());
    if (!type_ok) return it.key() + " has the wrong type";
    if (it.value().is_array() && property.contains("items")) {
      const auto& item_schema = property.at("items");
      for (const auto& item : it.value()) {
        if (item_schema.value("type", std::string()) == "string" && !item.is_string()) {
          return it.key() + " items must be strings";
        }
        if (item_schema.contains("enum") &&
            std::find(item_schema.at("enum").begin(), item_schema.at("enum").end(), item) ==
                item_schema.at("enum").end()) return it.key() + " contains an invalid value";
      }
    }
    if (it.value().is_string() && property.contains("minLength") &&
        it.value().get_ref<const std::string&>().size() < property.at("minLength").get<std::size_t>()) {
      return it.key() + " is too short";
    }
    if (it.value().is_number_integer()) {
      if (it.value().is_number_unsigned()) {
        const auto value = it.value().get<std::uint64_t>();
        if ((property.contains("minimum") && property.at("minimum").get<std::uint64_t>() > value) ||
            (property.contains("maximum") && value > property.at("maximum").get<std::uint64_t>())) {
          return it.key() + " is out of range";
        }
      } else {
        const auto value = it.value().get<std::int64_t>();
        if ((property.contains("minimum") && value < property.at("minimum").get<std::int64_t>()) ||
            (property.contains("maximum") && value > property.at("maximum").get<std::int64_t>())) {
          return it.key() + " is out of range";
        }
      }
    }
  }
  return std::nullopt;
}

// A screenshot reaches the client once, as the image item. The text item and
// structuredContent carry the metadata only, plus the MIME type and the decoded
// size -- the same shape the CLI's MCP server sends. Sending the base64 in all
// three tripled every screenshot, 0.5-0.9 MB for an ordinary page.
nlohmann::json ScreenshotContent(nlohmann::json* body) {
  const std::string image = (*body)["image"].get<std::string>();
  body->erase("image");
  const std::string mime_type = "image/" + body->value("format", std::string("png"));
  const std::size_t padding = image.size() >= 2 && image[image.size() - 2] == '=' ? 2
                              : !image.empty() && image.back() == '=' ? 1 : 0;
  (*body)["mimeType"] = mime_type;
  (*body)["imageBytes"] = image.size() * 3 / 4 - padding;
  return nlohmann::json::array({{{"type", "text"}, {"text", body->dump()}},
                                {{"type", "image"}, {"data", image}, {"mimeType", mime_type}}});
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
    if (const auto invalid = ValidateToolArguments(InputSchema(match->http_endpoint), arguments)) {
      return ReplyOrNothing(notification, JsonRpcError(id, -32602, *invalid));
    }

    const bool page_text = match->http_endpoint == "get-page-text";
    json forwarded = arguments;
    std::size_t max_chars = desktop_mcp::kDefaultPageTextMaxChars;
    if (page_text && forwarded.contains("maxChars")) {
      max_chars = static_cast<std::size_t>(forwarded["maxChars"].get<std::uint64_t>());
      forwarded.erase("maxChars");
    }
    const DesktopRouter::Result result =
        impl_->router->Dispatch(match->http_endpoint, forwarded);
    const bool screenshot = match->http_endpoint == "screenshot" || match->http_endpoint == "screenshot-annotated";
    json content;
    json structured = page_text ? desktop_mcp::LimitPageText(result.body, max_chars) : result.body;
    if (screenshot && result.body.value("success", false) && result.body.contains("image") &&
        result.body["image"].is_string()) {
      content = ScreenshotContent(&structured);
    } else {
      content = {{{"type", "text"}, {"text", structured.dump()}}};
    }
    const json response = JsonRpcResult(id, {{"content", content},
                                               {"structuredContent", structured},
                                               {"isError", !result.body.value("success", false)}});
    return ReplyOrNothing(notification, response);
  }

  const json response = JsonRpcError(id, -32601, "Unsupported method: " + method);
  return ReplyOrNothing(notification, response);
}

}  // namespace kelpie
