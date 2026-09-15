#include "kelpie/desktop_mcp_server.h"

#include <cassert>
#include <set>
#include <string>

#include "kelpie/desktop_router.h"
#include "kelpie/mcp_registry.h"

int main() {
  kelpie::DesktopRouter router;
  // This is the Windows desktop callable catalogue. Keeping the endpoint list
  // here makes registry/handler drift fail tools/list instead of advertising a placeholder.
  const std::set<std::string> endpoints = {
      "navigate", "back", "forward", "reload", "get-current-url", "set-home", "get-home",
      "close-browser", "bookmarks-list", "bookmarks-add", "bookmarks-remove", "bookmarks-clear",
      "history-list", "history-clear", "screenshot", "get-dom", "query-selector",
      "query-selector-all", "get-element-text", "get-attributes", "click", "fill", "type",
      "press-key", "select-option", "check", "uncheck", "scroll", "scroll-to-top",
      "scroll-to-bottom", "get-viewport", "get-device-info", "get-capabilities",
      "wait-for-element", "wait-for-navigation", "find-element", "find-button", "find-link",
      "find-input", "evaluate", "toast", "get-console-messages", "get-js-errors",
      "get-network-log", "clear-network-log", "clear-console", "get-accessibility-tree",
      "get-visible-elements", "get-page-text", "get-form-state", "get-dialog", "handle-dialog",
      "get-tabs", "new-tab", "switch-tab", "close-tab", "get-cookies", "set-cookie",
      "delete-cookies", "clear-cookies", "get-storage", "set-storage", "clear-storage",
      "resize-viewport", "reset-viewport", "set-fullscreen", "get-fullscreen",
  };
  for (const auto& endpoint : endpoints) {
    router.Register(endpoint, [](const nlohmann::json& params) {
      return nlohmann::json{{"success", true}, {"params", params}};
    });
  }

  kelpie::McpRegistry registry;
  kelpie::DesktopMcpServer server;
  server.SetRouter(&router);
  server.SetRegistry(&registry);

  kelpie::DesktopMcpServer::Config config;
  config.platform = kelpie::Platform::kWindows;
  config.engine = "chromium";

  const auto init = server.HandleRequest(
      {{"jsonrpc", "2.0"}, {"id", 1}, {"method", "initialize"},
       {"params", {{"protocolVersion", "2025-06-18"}}}}, config);
  assert(init["result"]["serverInfo"]["name"] == "kelpie-desktop");
  assert(init["result"]["protocolVersion"] == "2025-06-18");

  const auto tools = server.HandleRequest({{"jsonrpc", "2.0"}, {"id", 2}, {"method", "tools/list"}}, config);
  const auto& listed = tools["result"]["tools"];
  std::set<std::string> expected_names;
  for (const auto& tool : registry.all_tools()) {
    if (endpoints.find(tool.http_endpoint) != endpoints.end()) expected_names.insert(tool.name);
  }
  std::set<std::string> actual_names;
  for (const auto& tool : listed) {
    actual_names.insert(tool["name"].get<std::string>());
    const auto& schema = tool["inputSchema"];
    assert(schema["type"] == "object");
    assert(schema["additionalProperties"] == false);
    assert(schema["properties"].is_object());
    assert(schema["required"].is_array());
  }
  assert(actual_names == expected_names);
  assert(actual_names.find("kelpie_bookmarks_list") != actual_names.end());
  assert(actual_names.find("kelpie_history_list") != actual_names.end());
  assert(actual_names.find("kelpie_clear_cookies") != actual_names.end());
  assert(actual_names.find("kelpie_screenshot_annotated") == actual_names.end());

  const auto schema_for = [&listed](const char* name) -> const nlohmann::json& {
    for (const auto& tool : listed) if (tool["name"] == name) return tool["inputSchema"];
    assert(false); return listed[0]["inputSchema"];
  };
  const auto& fill = schema_for("kelpie_fill");
  assert(fill["required"] == nlohmann::json::array({"selector", "value"}));
  assert(fill["properties"]["value"]["minLength"] == 0);
  const auto& screenshot = schema_for("kelpie_screenshot");
  assert(screenshot["properties"]["format"]["const"] == "png");
  assert(!screenshot["properties"].contains("fullPage"));
  const auto& viewport = schema_for("kelpie_resize_viewport");
  assert(viewport["required"] == nlohmann::json::array({"width", "height"}));
  assert(viewport["properties"]["width"]["minimum"] == 1);
  const auto& bookmark_remove = schema_for("kelpie_bookmarks_remove");
  assert(bookmark_remove["required"] == nlohmann::json::array({"id"}));

  const auto notification = server.HandleRequest(
      {{"jsonrpc", "2.0"}, {"method", "notifications/initialized"}}, config);
  assert(notification.is_null());

  const auto bad_arguments = server.HandleRequest(
      {{"jsonrpc", "2.0"}, {"id", 7}, {"method", "tools/call"},
       {"params", {{"name", "kelpie_navigate"}, {"arguments", "bad"}}}}, config);
  assert(bad_arguments["error"]["code"] == -32602);
  const auto missing_fill = server.HandleRequest(
      {{"jsonrpc", "2.0"}, {"id", 8}, {"method", "tools/call"},
       {"params", {{"name", "kelpie_fill"}, {"arguments", {{"selector", "#name"}}}}}}, config);
  assert(missing_fill["error"]["code"] == -32602);
  const auto invalid_screenshot = server.HandleRequest(
      {{"jsonrpc", "2.0"}, {"id", 9}, {"method", "tools/call"},
       {"params", {{"name", "kelpie_screenshot"}, {"arguments", {{"format", "jpeg"}}}}}}, config);
  assert(invalid_screenshot["error"]["code"] == -32602);
  const auto empty_fill = server.HandleRequest(
      {{"jsonrpc", "2.0"}, {"id", 10}, {"method", "tools/call"},
       {"params", {{"name", "kelpie_fill"}, {"arguments", {{"selector", "#name"}, {"value", ""}}}}}}, config);
  assert(empty_fill["result"]["isError"] == false);
  const std::vector<std::pair<std::string, nlohmann::json>> parameter_fixtures = {
      {"kelpie_wait_for_element", {{"selector", "#ready"}, {"state", "visible"}, {"tabId", "second"}, {"generation", 9}, {"timeout", 1000}}},
      {"kelpie_find_element", {{"text", "Save"}, {"role", "button"}, {"selector", "button"}, {"tabId", "second"}, {"generation", 9}}},
      {"kelpie_find_input", {{"label", "Email"}, {"placeholder", "Email"}, {"name", "email"}, {"tabId", "second"}, {"generation", 9}}},
      {"kelpie_get_accessibility_tree", {{"root", "#app"}, {"interactableOnly", true}, {"maxDepth", 3}, {"tabId", "second"}, {"generation", 9}}},
      {"kelpie_get_visible_elements", {{"interactableOnly", true}, {"includeText", false}, {"tabId", "second"}, {"generation", 9}}},
      {"kelpie_get_page_text", {{"mode", "readable"}, {"selector", "main"}, {"tabId", "second"}, {"generation", 9}}},
      {"kelpie_get_form_state", {{"selector", "form"}, {"tabId", "second"}, {"generation", 9}}},
      {"kelpie_press_key", {{"key", "K"}, {"code", "KeyK"}, {"modifiers", {"Control", "Shift"}}, {"tabId", "second"}, {"generation", 9}}},
  };
  int fixture_id = 11;
  for (const auto& [name, arguments] : parameter_fixtures) {
    const auto reply = server.HandleRequest({{"jsonrpc", "2.0"}, {"id", fixture_id++}, {"method", "tools/call"},
        {"params", {{"name", name}, {"arguments", arguments}}}}, config);
    assert(reply.contains("result"));
  }
  const auto bad_modifier = server.HandleRequest({{"jsonrpc", "2.0"}, {"id", 99}, {"method", "tools/call"},
      {"params", {{"name", "kelpie_press_key"}, {"arguments", {{"key", "K"}, {"modifiers", {"Bogus"}}}}}}}, config);
  assert(bad_modifier.contains("error"));
  assert(bad_modifier.at("error").at("code") == -32602);
  const auto huge_viewport = server.HandleRequest({{"jsonrpc", "2.0"}, {"id", 100}, {"method", "tools/call"},
      {"params", {{"name", "kelpie_resize_viewport"}, {"arguments", {{"width", 4294967297ULL}, {"height", 720}}}}}}, config);
  assert(huge_viewport.contains("error"));
  assert(huge_viewport.at("error").at("code") == -32602);

  return 0;
}