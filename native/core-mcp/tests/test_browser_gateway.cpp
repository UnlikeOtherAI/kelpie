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
  for (const auto& fixture : json::parse(kelpie::browser_assets::cases)) {
    auto value = fixture["input"];
    const bool accepted = kelpie::ValidateBrowserJson(schema, &value);
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
  step = gateway.Advance({{"success", true}, {"result", {{"selector", "button:nth-child(1)"}}}});
  assert(step["method"] == "click");
  gateway.Advance({{"success", false}});
  assert(gateway.Begin(Request("tab.click", {{"ref", ref}}))["response"]["error"]["code"] == "STALE_REFERENCE");
}
void Mcp() {
  kelpie::BrowserGateway gateway({{"nativeMethods", {"screenshot"}}, {"requireAuthorization", false}});
  auto step = gateway.BeginMcp({{"jsonrpc", "2.0"}, {"id", 1}, {"method", "tools/list"}});
  const auto tools = step["response"]["result"]["tools"];
  assert(tools.size() == 3);
  assert(tools.dump().size() < 24000);
  step = gateway.BeginMcp({{"jsonrpc", "2.0"}, {"id", 2}, {"method", "tools/call"}, {"params", {{"name", "kelpie_browser_control"}, {"arguments", {{"request", Request("tab.screenshot")}}}}}});
  assert(step["method"] == "screenshot");
  step = gateway.Advance({{"success", true}, {"image", "AQID"}});
  const auto content = step["response"]["result"]["content"];
  assert(content.size() == 2);
  assert(content[0]["type"] == "image");
  assert(content[1]["text"].get<std::string>().find("AQID") == std::string::npos);
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
}
void CAbi() {
  const auto gateway = kelpie_browser_gateway_create("{\"nativeMethods\":[]}");
  assert(gateway);
  char* result = kelpie_browser_gateway_begin(gateway, "{\"version\":1,\"method\":\"documentation\"}");
  assert(json::parse(result)["kind"] == "authorize");
  kelpie_mcp_free_string(result);
  result = kelpie_browser_gateway_advance(gateway, "{\"success\":true}");
  assert(json::parse(result)["response"]["ok"] == true);
  kelpie_mcp_free_string(result);
  kelpie_browser_gateway_destroy(gateway);
}
int main() { Contracts(); Sequencing(); References(); Mcp(); SelectedAndMapping(); CAbi(); std::cout << "Browser gateway contracts passed\n"; }
