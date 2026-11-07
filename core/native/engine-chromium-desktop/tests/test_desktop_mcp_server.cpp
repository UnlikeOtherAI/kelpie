#include "kelpie/desktop_mcp_server.h"

#include <cassert>
#include <atomic>
#include <chrono>
#include <memory>
#include <optional>
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
  std::string live_document = "document-1";
  bool live_active = true;
  int guarded_effects = 0;
  std::optional<kelpie::TabLease> late_lease;
  for (const auto& endpoint : endpoints) {
    router.Register(endpoint, [&, endpoint](const nlohmann::json& params) {
      if (endpoint == "navigate" && kelpie::ScopedBrowserControlLease::Current()) {
        late_lease = *kelpie::ScopedBrowserControlLease::Current();
        if (!late_lease->document_version || *late_lease->document_version != live_document ||
            (late_lease->require_active && !live_active) ||
            (late_lease->cancelled && late_lease->cancelled->load()) ||
            (late_lease->deadline && std::chrono::steady_clock::now() >= *late_lease->deadline))
          return nlohmann::json{{"success", false}, {"error", {{"code", "TAB_STALE"}}}};
        ++guarded_effects;
      }
      return nlohmann::json{{"success", true}, {"params", params}};
    });
  }
  router.BeforeDispatch([&](std::string_view method, const nlohmann::json&) {
    if (method == "navigate") { live_document = "document-2"; live_active = false; }
    return std::shared_ptr<void>();
  });

  kelpie::McpRegistry registry;
  kelpie::DesktopMcpServer server;
  server.SetRouter(&router);
  server.SetRegistry(&registry);

  kelpie::DesktopMcpServer::Config config;
  config.platform = kelpie::Platform::kWindows;
  config.engine = "chromium";

  auto cancel = std::make_shared<std::atomic<bool>>(false);
  kelpie::TabLease pinned{"owned", 7, "document-1", cancel,
      std::chrono::steady_clock::now() + std::chrono::seconds(20), true};
  const auto raced_control = server.HandleBrowserRequestAuthorized(
      {{"version", 1}, {"method", "tab.goto"}, {"tabId", "owned"},
       {"params", {{"url", "https://example.org"}}}}, config, [] { return true; }, pinned);
  assert(!raced_control["ok"].get<bool>() && guarded_effects == 0);
  assert(late_lease && late_lease->document_version == "document-1" && late_lease->cancelled == cancel);
  assert(!kelpie::ScopedBrowserControlLease::Current());
  // A renderer callback that outlives the account request retains the original
  // lease and cannot re-resolve onto the document that replaced it mid-dispatch.
  live_document = "document-2";
  if (late_lease->document_version == live_document) ++guarded_effects;
  assert(guarded_effects == 0);
  router.BeforeDispatch([](std::string_view, const nlohmann::json&) { return std::shared_ptr<void>(); });
  live_document = "document-1"; live_active = true;

  const auto init = server.HandleRequest(
      {{"jsonrpc", "2.0"}, {"id", 1}, {"method", "initialize"},
       {"params", {{"protocolVersion", "2025-06-18"}}}}, config);
  assert(init["result"]["serverInfo"]["name"] == "kelpie");
  assert(init["result"]["protocolVersion"] == "2025-06-18");

  const auto tools = server.HandleRequest({{"jsonrpc", "2.0"}, {"id", 2}, {"method", "tools/list"}}, config);
  const auto& listed = tools["result"]["tools"];
  assert(listed.size() == 4);
  assert(listed.dump().size() < 24000);
  assert(listed[0]["name"] == "kelpie_browser_control");
  const auto names = server.HandleRequest({{"jsonrpc", "2.0"}, {"id", 3}, {"method", "tools/call"},
    {"params", {{"name", "kelpie_extensions"}}}}, config);
  assert(names["result"]["content"].dump().find("kelpie_bookmarks_list") != std::string::npos);
  const auto discovered = server.HandleRequest({{"jsonrpc", "2.0"}, {"id", 4}, {"method", "tools/call"},
    {"params", {{"name", "kelpie_extension_tools"}, {"arguments", {{"names", {"kelpie_fill", "kelpie_screenshot", "kelpie_resize_viewport", "kelpie_bookmarks_remove"}}}}}}}, config);
  const auto schemas = nlohmann::json::parse(discovered["result"]["content"][0]["text"].get<std::string>())["value"];
  const auto schema_for = [&schemas](const char* name) -> const nlohmann::json& {
    for (const auto& tool : schemas) if (tool["name"] == name) return tool["inputSchema"];
    assert(false); return schemas[0]["inputSchema"];
  };
  const auto rich_call = server.HandleRequest({{"jsonrpc", "2.0"}, {"id", 5}, {"method", "tools/call"},
    {"params", {{"name", "kelpie_extension"}, {"arguments", {{"name", "kelpie_bookmarks_list"}, {"arguments", nlohmann::json::object()}}}}}}, config);
  assert(rich_call["result"]["isError"] == false);
  const auto& fill = schema_for("kelpie_fill");
  assert(fill["required"] == nlohmann::json::array({"selector", "value"}));
  assert(fill["properties"]["value"]["type"] == "string");
  const auto& screenshot = schema_for("kelpie_screenshot");
  assert(screenshot["properties"]["format"]["enum"] == nlohmann::json::array({"png", "jpeg"}));
  assert(screenshot["properties"]["fullPage"]["type"] == "boolean");
  const auto& viewport = schema_for("kelpie_resize_viewport");
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
  const auto jpeg_screenshot = server.HandleRequest(
      {{"jsonrpc", "2.0"}, {"id", 9}, {"method", "tools/call"},
       {"params", {{"name", "kelpie_screenshot"}, {"arguments", {{"format", "jpeg"}}}}}}, config);
  assert(jpeg_screenshot["result"]["isError"] == false);
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
      {"kelpie_set_cookie", {{"name", "session"}, {"value", ""}, {"sameSite", "Lax"}, {"tabId", "second"}, {"generation", 9}}},
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
  const auto bad_same_site = server.HandleRequest({{"jsonrpc", "2.0"}, {"id", 101}, {"method", "tools/call"},
      {"params", {{"name", "kelpie_set_cookie"}, {"arguments", {{"name", "session"}, {"value", ""}, {"sameSite", "invalid"}}}}}}, config);
  assert(bad_same_site.contains("error"));
  assert(bad_same_site.at("error").at("code") == -32602);

  std::string observed;
  bool enforce_pinned_reader = false;
  int observed_action_effects = 0;
  server.SetFixedReader([&](const nlohmann::json& params) {
    const std::string expression = params.at("expression");
    if (enforce_pinned_reader) {
      const auto& scoped = kelpie::ScopedBrowserControlLease::Current();
      if (!scoped || !scoped->document_version || *scoped->document_version != live_document ||
          (scoped->require_active && !live_active) || (scoped->cancelled && scoped->cancelled->load()) ||
          (scoped->deadline && std::chrono::steady_clock::now() >= *scoped->deadline))
        return nlohmann::json{{"success", false}, {"error", {{"code", "TAB_STALE"}}}};
      if (expression.find("tab.click") != std::string::npos) ++observed_action_effects;
    }
    const auto start = expression.find("\"prefix\":\"") + 10;
    observed = expression.substr(start, expression.find('"', start) - start) + "1";
    return nlohmann::json{{"success", true}, {"result", {{"url", "https://same.test"}, {"title", "title"}, {"text", "button"},
      {"elements", {{{"ref", observed}, {"role", "button"}, {"name", "Button"}}}}}}};
  });
  enforce_pinned_reader = true;
  live_document = "document-1";
  live_active = true;
  const auto account_snapshot = server.HandleBrowserRequestAuthorized(
      {{"version", 1}, {"method", "tab.snapshot"}, {"tabId", "owned"}}, config,
      [] { return true; }, pinned);
  assert(account_snapshot["ok"] == true && !observed.empty());
  const auto account_click = server.HandleBrowserRequestAuthorized(
      {{"version", 1}, {"method", "tab.click"}, {"tabId", "owned"},
       {"params", {{"ref", observed}}}}, config,
      [&] { live_document = "document-3"; return true; }, pinned);
  assert(account_click["ok"] == false && observed_action_effects == 0);
  assert(!kelpie::ScopedBrowserControlLease::Current());
  enforce_pinned_reader = false;
  assert(server.HandleBrowserRequest({{"version", 1}, {"method", "tab.snapshot"}, {"tabId", "a"}}, config)["ok"] == true);
  // Renderer callbacks only enqueue; same-URL restoration cannot revive an old observed handle.
  server.NotifyDocumentChanged();
  const auto stale = server.HandleBrowserRequest({{"version", 1}, {"method", "tab.click"}, {"tabId", "a"}, {"params", {{"ref", observed}}}}, config);
  assert(stale["error"]["code"] == "STALE_REFERENCE");
  assert(server.HandleBrowserRequest({{"version",1},{"method","tab.snapshot"},{"tabId","a"}},config)["ok"]==true);
  { const auto remote=server.GuardDispatch("switch-tab",{{"tabId","a"}});assert(remote); }
  // WSS/native selection shares admission and invalidates the public gateway's refs.
  assert(server.HandleBrowserRequest({{"version",1},{"method","tab.click"},{"tabId","a"},
      {"params",{{"ref",observed}}}},config)["error"]["code"]=="STALE_REFERENCE");

  bool pending = true;
  server.SetPendingCheck([&] { return pending; });
  assert(server.HandleBrowserRequest({{"version", 1}, {"method", "tabs.list"}}, config)["error"]["code"] == "BUSY");
  const auto busy_rpc = server.HandleRequest({{"jsonrpc", "2.0"}, {"id", 123}, {"method", "tools/call"},
      {"params", {{"name", "kelpie_browser_control"}, {"arguments", {{"request", {{"version", 1}, {"method", "tabs.list"}}}}}}}}, config);
  assert(busy_rpc["id"] == 123 && busy_rpc["error"]["code"] == -32000);
  {
    const auto observation = server.GuardDispatch("get-dialog", nlohmann::json::object());
    assert(observation);
  }
  {
    const auto handling = server.GuardDispatch("handle-dialog", {{"action", "accept"}});
    assert(handling);
  }
  for (const auto* name : {"kelpie_get_dialog", "kelpie_handle_dialog"}) {
    const auto arguments = std::string(name) == "kelpie_handle_dialog"
      ? nlohmann::json{{"action", "accept"}} : nlohmann::json::object();
    const auto recovery = server.HandleRequest({{"jsonrpc", "2.0"}, {"id", 125}, {"method", "tools/call"},
      {"params", {{"name", "kelpie_extension"}, {"arguments", {{"name", name}, {"arguments", arguments}}}}}}, config);
    assert(recovery["result"]["isError"] == false);
    // Recovery alone does not clear ownership; only the actual late callback can.
    assert(server.HandleBrowserRequest({{"version", 1}, {"method", "tabs.list"}}, config)["error"]["code"] == "BUSY");
  }
  bool refused = false;
  try { server.GuardDispatch("click", {{"selector", "button"}}); }
  catch (const std::runtime_error&) { refused = true; }
  assert(refused);
  pending = false; // The late renderer callback retired execution ownership.
  assert(server.HandleBrowserRequest({{"version", 1}, {"method", "documentation"}}, config)["ok"] == true);
  bool nested = false;
  router.Register("ai-infer", [&](const nlohmann::json&) {
    const auto context = server.HandleBrowserRequest({{"version", 1}, {"method", "documentation"}}, config);
    nested = context.value("ok", false);
    return nlohmann::json{{"success", nested}};
  });
  server.SetRouter(&router);
  const auto inference = server.HandleRequest({{"jsonrpc", "2.0"}, {"id", 124}, {"method", "tools/call"},
      {"params", {{"name", "kelpie_extension"}, {"arguments", {{"name", "kelpie_ai_ask"}, {"arguments", {{"context", "page_text"}}}}}}}}, config);
  assert(nested && inference["result"]["isError"] == false);
  return 0;
}
