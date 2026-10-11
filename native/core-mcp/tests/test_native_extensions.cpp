#include "kelpie/native_extension_schema.h"
#include "kelpie/mcp_registry.h"
#include "kelpie/browser_gateway.h"
#include "browser_schema.h"
#include "browser_contract.h"
#include <cassert>
#include <iostream>
using json = nlohmann::json;
void Accept(std::string_view endpoint, json arguments) {
  assert(kelpie::ValidateBrowserJson(kelpie::NativeExtensionInputSchema(endpoint), &arguments));
}
int main() {
  for (const auto& tool : kelpie::McpRegistry().all_tools()) {
    const auto schema = kelpie::NativeExtensionInputSchema(tool.http_endpoint);
    if (!schema.is_object()) std::cerr << "Missing native contract: " << tool.http_endpoint << "\n";
    assert(schema.is_object());
    assert(!schema["properties"].contains("device"));
  }
  for (const auto& fixture : json::parse(kelpie::browser_assets::extension_cases)) {
    auto body = fixture["body"];
    const std::string endpoint = fixture["endpoint"];
    if (!kelpie::ValidateBrowserJson(kelpie::NativeExtensionInputSchema(endpoint), &body)) {
      std::cerr << "Forwarded body refused: " << endpoint << "\n"; assert(false);
    }
  }
  Accept("tap", {{"x", 12.5}, {"y", 22}, {"tabId", "a"}});
  Accept("highlight", {{"selector", "button"}, {"color", "red"}, {"durationMs", 0}});
  Accept("scroll2", {{"selector", "button"}, {"position", "center"}, {"maxScrolls", 4}});
  Accept("screenshot", {{"format", "jpeg"}, {"quality", 75}, {"fullPage", true}, {"resolution", "native"}});
  Accept("click-annotation", {{"index", 2}});
  Accept("swipe", {{"from", {{"x", 1}, {"y", 2}}}, {"to", {{"x", 4}, {"y", 5}}}, {"steps", 6}});
  Accept("set-clipboard", {{"text", "value"}});
  Accept("set-geolocation", {{"latitude", 50}, {"longitude", 14}, {"accuracy", 1}});
  Accept("ai-infer", {{"audio", "AQID"}, {"maxSteps", 10}, {"allowActions", false}});
  Accept("ai-endpoint-save", {{"name", "local"}, {"baseURL", "http://localhost:1234/v1"}, {"capabilities", {{"vision", nullptr}, {"contextWindow", 128}}}});
  json invalid = {{"name", "local"}, {"baseURL", "http://localhost:1234/v1"}, {"capabilities", {{"contextWindow", 0}}}};
  assert(!kelpie::ValidateBrowserJson(kelpie::NativeExtensionInputSchema("ai-endpoint-save"), &invalid));
  invalid = {{"rules", {{{"pattern", "*"}, {"action", "mock"}, {"mockResponse", {{"status", 200}, {"headers", {{"test", 1}}}, {"body", ""}}}}}};
  assert(!kelpie::ValidateBrowserJson(kelpie::NativeExtensionInputSchema("set-request-interception"), &invalid));
  invalid = {{"text", 1}};
  assert(!kelpie::ValidateBrowserJson(kelpie::NativeExtensionInputSchema("set-clipboard"), &invalid));
  invalid = json::object();
  assert(!kelpie::ValidateBrowserJson(kelpie::NativeExtensionInputSchema("missing"), &invalid));
  const json extension = {{"name", "kelpie_tap"}, {"method", "tap"}, {"inputSchema", kelpie::NativeExtensionInputSchema("tap")}, {"mutates", true}};
  kelpie::BrowserGateway gateway({{"nativeMethods", {"tap"}}, {"requireAuthorization", false}, {"extensions", json::array({extension})}});
  auto step = gateway.BeginMcp({{"jsonrpc", "2.0"}, {"id", 1}, {"method", "tools/call"}, {"params", {{"name", "kelpie_extension"}, {"arguments", {{"name", "kelpie_tap"}, {"arguments", {{"x", 1}, {"y", 2}}}}}}}});
  assert(step["method"] == "tap" && step["params"]["x"] == 1);
  assert(gateway.Advance({{"success", true}})["response"]["result"]["isError"] == false);
  std::cout << "Native extension catalog and forwarding parity passed\n";
}
