#include "kelpie/browser_gateway.h"
#include "kelpie/browser_gateway_c_api.h"
#include "kelpie/mcp_c_api.h"
#include "browser_schema.h"
#include "browser_contract.h"
#include <cassert>
#include <iostream>
using json = nlohmann::json;
json Request(const std::string& method, json params = json::object(), const std::string& tab = "a") {
  return {{"version", 1}, {"method", method}, {"tabId", tab}, {"params", params}};
}
void Contracts() {
  const auto schema = json::parse(kelpie::browser_assets::request_schema);
  int index = 0;
  for (const auto& fixture : json::parse(kelpie::browser_assets::cases)) {
    auto value = fixture["input"];
    const bool accepted = kelpie::ValidateBrowserJson(schema, &value);
    if (accepted != fixture["accepted"]) std::cerr << "Schema fixture mismatch " << index << " accepted=" << accepted << " expected=" << fixture["accepted"] << "\n";
    ++index;
    assert(accepted == fixture["accepted"]);
    if (accepted) assert(value == fixture["output"]);
  }
}
void Sequencing() {
  kelpie::BrowserGateway gateway({{"nativeMethods", {"navigate", "get-current-url", "switch-tab", "click", "type"}}, {"fixedReader", true}});
  auto step = gateway.Begin(Request("tab.goto", {{"url", "https://example.org"}}));
  assert(step["kind"] == "authorize");
  assert(gateway.Begin(Request("tab.url"))["response"]["error"]["code"] == "BUSY");
  assert(gateway.Next() == step);
  step = gateway.Advance({{"success", true}});
  assert(step["method"] == "navigate");
  step = gateway.Advance({{"success", false}, {"error", "SECRET script token"}});
  assert(step["response"]["error"]["mayHaveCompleted"] == true);
  assert(step.dump().find("SECRET") == std::string::npos);
  step = gateway.Begin(Request("tab.url"));
  step = gateway.Advance({{"success", false}});
  assert(step["response"]["error"]["mayHaveCompleted"] == false);
  gateway.Begin(Request("tab.goto", {{"url", "url"}}));
  gateway.Advance({{"success", true}});
  assert(gateway.Cancel()["response"]["error"]["mayHaveCompleted"] == true);
  step = gateway.Begin(Request("locator.fill", {{"locator", {{{"kind", "css"}, {"value", "input"}}}}, {"value", "x"}}));
  assert(step["response"]["error"]["code"] == "UNSUPPORTED");
}
void References() {
  kelpie::BrowserGateway gateway({{"nativeMethods", {"click", "type", "navigate"}}, {"fixedReader", true}, {"requireAuthorization", false}});
  auto step = gateway.Begin(Request("tab.snapshot"));
  assert(step["method"] == "browser-control-evaluate");
  std::string expression = step["params"]["expression"];
  const auto start = expression.find("\"prefix\":\"") + 10;
  const auto end = expression.find('"', start);
  const std::string ref = expression.substr(start, end - start) + "1";
  json snapshot = {{"url", "url"}, {"title", "title"}, {"text", "button Save"}, {"elements", {{{"ref", ref}, {"role", "button"}, {"name", "Save"}}}}};
  step = gateway.Advance({{"success", true}, {"result", snapshot}});
  assert(step["response"]["ok"] == true);
  step = gateway.Begin(Request("tab.click", {{"ref", ref}}, "b"));
  assert(step["response"]["error"]["code"] == "STALE_REFERENCE");
  step = gateway.Begin(Request("tab.click", {{"ref", ref}}));
  assert(step["method"] == "browser-control-evaluate");
  assert(step["mutates"] == true);
  step = gateway.Advance({{"success", true}, {"result", {{"error", "STALE_REFERENCE"}, {"mayHaveCompleted", false}}}});
  assert(step["response"]["error"]["mayHaveCompleted"] == false);
  assert(gateway.Begin(Request("tab.click", {{"ref", ref}}))["response"]["error"]["code"] == "STALE_REFERENCE");
  step = gateway.Begin(Request("tab.snapshot"));
  expression = step["params"]["expression"];
  const auto fresh_start = expression.find("\"prefix\":\"") + 10;
  const std::string fresh_ref = expression.substr(fresh_start, expression.find('"', fresh_start) - fresh_start) + "1";
  snapshot["elements"][0]["ref"] = fresh_ref;
  gateway.Advance({{"success", true}, {"result", snapshot}});
  gateway.InvalidateReferences("a");
  assert(gateway.Begin(Request("tab.click", {{"ref", fresh_ref}}))["response"]["error"]["code"] == "STALE_REFERENCE");
}
void Mcp() {
  kelpie::BrowserGateway gateway({{"nativeMethods", {"screenshot"}}, {"requireAuthorization", false}});
  auto step = gateway.BeginMcp({{"jsonrpc", "2.0"}, {"id", 1}, {"method", "tools/list"}});
  const auto tools = step["response"]["result"]["tools"];
  assert(tools.size() == 4);
  assert(tools.dump().size() < 24000);
  step = gateway.BeginMcp({{"jsonrpc", "2.0"}, {"id", 2}, {"method", "tools/call"}, {"params", {{"name", "kelpie_browser_control"}, {"arguments", {{"request", Request("tab.screenshot")}}}}}});
  assert(step["method"] == "screenshot");
  step = gateway.Advance({{"success", true}, {"image", "AQID"}});
  const auto content = step["response"]["result"]["content"];
  assert(content.size() == 2);
  assert(content[0]["type"] == "image");
  assert(content[1]["text"].get<std::string>().find("AQID") == std::string::npos);
  const json extension = {{"name", "shot"}, {"method", "screenshot"}, {"mutates", false}, {"inputSchema", {{"type", "object"}}}};
  kelpie::BrowserGateway rich({{"nativeMethods", {"screenshot"}}, {"requireAuthorization", false}, {"extensions", json::array({extension})}});
  rich.BeginMcp({{"jsonrpc", "2.0"}, {"id", 3}, {"method", "tools/call"}, {"params", {{"name", "kelpie_extension"}, {"arguments", {{"name", "shot"}, {"arguments", json::object()}}}}}});
  step = rich.Advance({{"success", true}, {"image", "AQID"}, {"format", "jpeg"}});
  const auto blocks = step["response"]["result"]["content"];
  assert(blocks.size() == 2 && blocks[0]["mimeType"] == "image/jpeg");
  assert(blocks[1]["text"].get<std::string>().find("AQID") == std::string::npos);
  kelpie::BrowserGateway fallback({{"nativeMethods", {"navigate", "get-current-url"}}, {"browserAvailable", false}});
  assert(fallback.Capabilities()["methods"].size() == 2);
  assert(fallback.Begin(Request("tab.goto", {{"url", "url"}}))["response"]["error"]["code"] == "UNSUPPORTED");
}
void ExtensionReachability() {
  const json schema = {{"type", "object"}, {"properties", {{"url", {{"type", "string"}}}}}, {"required", {"url"}}, {"additionalProperties", false}};
  const json tool = {{"name", "kelpie_bookmarks_add"}, {"method", "bookmarks-add"}, {"mutates", true}, {"inputSchema", schema}};
  kelpie::BrowserGateway gateway({{"nativeMethods", {"bookmarks-add"}}, {"requireAuthorization", false}, {"extensions", json::array({tool})}});
  auto step = gateway.BeginMcp({{"jsonrpc", "2.0"}, {"id", 1}, {"method", "tools/call"}, {"params", {{"name", "kelpie_extension"}, {"arguments", {{"name", "kelpie_bookmarks_add"}, {"arguments", {{"url", "https://example.org"}}}}}}}});
  assert(step["method"] == "bookmarks-add");
  assert(step["params"]["url"] == "https://example.org");
  assert(gateway.Advance({{"success", true}})["response"]["result"]["isError"] == false);
  const json nullable_tool = {{"name", "mutable"}, {"method", "bookmarks-add"}, {"inputSchema", {{"type", "object"}}}};
  kelpie::BrowserGateway nullable({{"nativeMethods", {"bookmarks-add"}}, {"requireAuthorization", false}, {"extensions", json::array({nullable_tool})}});
  nullable.BeginMcp({{"jsonrpc", "2.0"}, {"id", 2}, {"method", "tools/call"}, {"params", {{"name", "mutable"}, {"arguments", {{"tabId", nullptr}}}}}});
  assert(nullable.Advance({{"success", true}})["response"]["result"]["isError"] == false);
}
void ReadOnlySnapshotLifetime() {
  for (int turn = 0; turn < 3; ++turn) {
    kelpie::BrowserGateway gateway({{"nativeMethods", {"click", "type"}}, {"fixedReader", true},
      {"allowActions", false}, {"requireAuthorization", false}});
    const auto step = gateway.Begin(Request("tab.snapshot"));
    const std::string expression = step["params"]["expression"];
    assert(expression.find(kelpie::browser_assets::reader) != std::string::npos);
    assert(expression.find(kelpie::browser_assets::remember) == std::string::npos);
    assert(expression.find(".snapshot") != std::string::npos);
    gateway.Cancel();
    assert(gateway.Begin(Request("tab.click", {{"ref", "e1"}}))["response"]["error"]["code"] == "UNSUPPORTED");
  }
}
void SelectedAndMapping() {
  const json config = {{"nativeMethods", {"get-tabs", "switch-tab", "scroll", "screenshot", "get-current-url", "navigate"}}, {"targeting", "selected"}, {"allowActions", false}, {"requireAuthorization", false}};
  kelpie::BrowserGateway read_only(config);
  auto step = read_only.Begin(Request("tab.url"));
  assert(step["method"] == "get-tabs");
  step = read_only.Advance({{"success", true}, {"activeTab", "a"}, {"tabs", {{{"id", "a"}, {"active", true}}}}});
  assert(step["method"] == "get-current-url");
  read_only.Advance({{"success", true}, {"url", "url"}});
  read_only.Begin(Request("tab.url", json::object(), "b"));
  step = read_only.Advance({{"success", true}, {"activeTab", "a"}});
  assert(step["response"]["error"]["code"] == "ACCESS_DENIED");
  assert(step["response"]["error"]["mayHaveCompleted"] == false);
  step = read_only.Begin(Request("tab.screenshot", {{"fullPage", true}}, "b"));
  assert(step["kind"] == "complete");
  assert(step["response"]["error"]["mayHaveCompleted"] == false);
  auto writable = config; writable["allowActions"] = true;
  kelpie::BrowserGateway actions(writable);
  step = actions.Begin(Request("page.scroll", {{"deltaY", 42}}));
  step = actions.Advance({{"success", true}, {"activeTab", "b"}});
  assert(step["method"] == "switch-tab");
  step = actions.Advance({{"success", true}});
  assert(step["method"] == "scroll");
  assert(step["params"]["deltaX"] == 0);
  assert(step["params"]["deltaY"] == 42);
  step = actions.Advance({{"success", false}});
  assert(step["response"]["error"]["mayHaveCompleted"] == true);
  kelpie::BrowserGateway direct({{"nativeMethods", {"navigate", "screenshot"}}, {"requireAuthorization", false}});
  step = direct.Begin(Request("tab.goto", {{"url", "url"}, {"timeoutMs", 234}}));
  assert(step["params"]["timeout"] == 234);
  assert(!step["params"].contains("timeoutMs"));
  direct.Cancel();
  step = direct.Begin(Request("tab.screenshot", {{"fullPage", false}}));
  assert(step["method"] == "screenshot");
  assert(!step["params"].contains("fullPage"));
  step = direct.Advance({{"success", true}, {"image", "AQID"}, {"format", "webp"}});
  assert(step["response"]["value"]["mimeType"] == "image/webp");
  direct.Begin(Request("tab.screenshot"));
  assert(direct.Advance({{"success", true}, {"image", "AQID"}, {"format", "invalid"}})["response"]["error"]["code"] == "COMMAND_FAILED");
}
void CAbi() {
  assert(!kelpie_browser_selector_snapshot_expression(nullptr));
  assert(!kelpie_browser_selector_snapshot_expression("[]"));
  assert(!kelpie_browser_selector_snapshot_expression(std::string(4097, 'x').c_str()));
  char* reader = kelpie_browser_selector_snapshot_expression("{\"maxChars\":6000,\"maxElements\":150}");
  assert(reader && json::parse(reader)["expression"] == kelpie::CollectBrowserSelectorSnapshotExpression({{"maxChars",6000},{"maxElements",150}}));
  kelpie_mcp_free_string(reader);
  const auto gateway = kelpie_browser_gateway_create("{\"nativeMethods\":[]}");
  assert(gateway);
  char* result = kelpie_browser_gateway_begin(gateway, "{\"version\":1,\"method\":\"documentation\"}");
  assert(json::parse(result)["kind"] == "authorize");
  kelpie_mcp_free_string(result);
  result = kelpie_browser_gateway_advance(gateway, "{\"success\":true}");
  assert(json::parse(result)["response"]["ok"] == true);
  kelpie_mcp_free_string(result);
  kelpie_browser_gateway_destroy(gateway);
  const auto large_gateway = kelpie_browser_gateway_create("{\"nativeMethods\":[\"type\"],\"fixedReader\":true}");
  // JSON escaping can make a valid 65,536-code-unit string much larger than 128KiB.
  std::string escaped;
  for (int index = 0; index < 65536; ++index) escaped += "\\u0001";
  const std::string large_request = "{\"version\":1,\"method\":\"tab.type\",\"tabId\":\"a\",\"params\":{\"ref\":\"unobserved\",\"text\":\"" + escaped + "\"}}";
  result = kelpie_browser_gateway_begin(large_gateway, large_request.c_str());
  assert(json::parse(result)["response"]["error"]["code"] == "STALE_REFERENCE");
  kelpie_mcp_free_string(result);
  std::string unicode;
  for (int index = 0; index < 32768; ++index) unicode += "\xf0\x9f\x98\x80";
  const auto unicode_request = Request("tab.type", {{"ref", "unobserved"}, {"text", unicode}}).dump();
  result = kelpie_browser_gateway_begin(large_gateway, unicode_request.c_str());
  assert(json::parse(result)["response"]["error"]["code"] == "STALE_REFERENCE");
  kelpie_mcp_free_string(result);
  kelpie_browser_gateway_destroy(large_gateway);
}
void Notifications() {
  kelpie::BrowserGateway gateway(json{{"nativeMethods", json::array()}});
  assert(gateway.BeginMcp({{"jsonrpc", "2.0"}, {"method", "notifications/unknown"}})["response"].is_null());
  assert(gateway.BeginMcp({{"jsonrpc", "2.0"}, {"method", "tools/call"}, {"params", {{"name", 123}}}})["response"].is_null());
}
int main() { ReadOnlySnapshotLifetime(); Notifications(); Contracts(); Sequencing(); References(); Mcp(); ExtensionReachability(); SelectedAndMapping(); CAbi(); std::cout << "Browser gateway contracts passed\n"; }
