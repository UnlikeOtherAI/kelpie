#include "kelpie/native_extension_schema.h"
#include "kelpie/mcp_registry.h"
#include "kelpie/mcp_c_api.h"
#include "kelpie/browser_gateway.h"
#include "browser_schema.h"
#include "browser_contract.h"
#include <cassert>
#include <iostream>
using json = nlohmann::json;
void Accept(std::string_view endpoint, json arguments) {
  assert(kelpie::ValidateBrowserJson(kelpie::NativeExtensionInputSchema(endpoint), &arguments));
}
void ScriptRegistryForwarding() {
  auto registry = kelpie_mcp_registry_create();
  char* encoded = kelpie_mcp_registry_tools_for_platform(registry, KELPIE_PLATFORM_WINDOWS);
  assert(encoded);
  const json extensions = json::parse(encoded);
  kelpie_mcp_free_string(encoded);
  kelpie_mcp_registry_destroy(registry);
  const json methods = {"play-script", "abort-script", "get-script-status", "get-script-artifact"};
  const std::vector<std::pair<std::string, json>> calls = {
    {"kelpie_play_script", {{"version", 1}, {"tabId", "a"}, {"actions", {{{"action", "wait"}, {"ms", 0}}}}}},
    {"kelpie_abort_script", {{"runId", "r"}}},
    {"kelpie_get_script_status", {{"runId", "r"}}},
    {"kelpie_get_script_artifact", {{"runId", "r"}, {"artifactId", "a"}, {"offset", 0}, {"length", 16}}}
  };
  auto rpc = [](const std::string& name, const json& body) {
    return json{{"jsonrpc", "2.0"}, {"id", 1}, {"method", "tools/call"},
      {"params", {{"name", "kelpie_extension"}, {"arguments", {{"name", name}, {"arguments", body}}}}}};
  };
  kelpie::BrowserGateway gateway({{"nativeMethods", methods}, {"extensions", extensions}});
  for (const auto& call : calls) {
    const std::string endpoint = call.first == "kelpie_play_script" ? "play-script" :
      call.first == "kelpie_abort_script" ? "abort-script" :
      call.first == "kelpie_get_script_status" ? "get-script-status" : "get-script-artifact";
    const bool mutates = endpoint == "play-script" || endpoint == "abort-script";
    bool found = false;
    for (const auto& tool : extensions) if (tool["name"] == call.first) {
      found = true; assert(tool["method"] == endpoint); assert(tool["mutates"] == mutates);
      assert(tool["inputSchema"] == kelpie::NativeExtensionInputSchema(endpoint));
      assert(!tool["inputSchema"]["properties"].contains("values"));
      assert(!tool["inputSchema"]["properties"].contains("secretEnv"));
    }
    assert(found);
    auto step = gateway.BeginMcp(rpc(call.first, call.second));
    assert(step["kind"] == "authorize"); assert(step["mutates"] == mutates);
    step = gateway.Advance({{"success", true}});
    assert(step["method"] == endpoint); assert(step["mutates"] == mutates);
    assert(gateway.Advance({{"success", true}, {"runId", "r"}})["response"]["result"]["isError"] == false);
  }
  kelpie::BrowserGateway read_only({{"nativeMethods", methods}, {"extensions", extensions}, {"allowActions", false}, {"requireAuthorization", false}});
  const auto visible = read_only.Extensions(nullptr);
  assert(visible.size() == 2);
  for (const auto& name : visible) assert(name == "kelpie_get_script_status" || name == "kelpie_get_script_artifact");
  assert(read_only.BeginMcp(rpc(calls[0].first, calls[0].second))["response"]["error"]["code"] == -32601);
  assert(read_only.BeginMcp(rpc(calls[1].first, calls[1].second))["response"]["error"]["code"] == -32601);
  for (std::size_t i : {2u, 3u}) {
    assert(read_only.BeginMcp(rpc(calls[i].first, calls[i].second))["kind"] == "dispatch");
    read_only.Advance({{"success", true}});
  }
  kelpie::BrowserGateway missing_route({{"nativeMethods", {"get-script-status"}}, {"extensions", extensions}, {"requireAuthorization", false}});
  assert(missing_route.Extensions(nullptr) == json::array({"kelpie_get_script_status"}));
  assert(missing_route.BeginMcp(rpc(calls[3].first, calls[3].second))["response"]["error"]["code"] == -32601);
  auto forged = calls[3].second; forged["owner"] = "forged";
  assert(gateway.BeginMcp(rpc(calls[3].first, forged))["response"]["error"]["code"] == -32602);
  auto oversized = calls[3].second; oversized["length"] = 1048577;
  assert(gateway.BeginMcp(rpc(calls[3].first, oversized))["response"]["error"]["code"] == -32602);
}
void ScriptSessionPreflightErrors() {
  const json script = {{"version", 1}, {"tabId", "a"}, {"sessionId", "foreign"},
    {"actions", {{{"action", "wait"}, {"ms", 0}}}}};
  const json extensions = json::array({
    {{"name", "kelpie_play_script"}, {"method", "play-script"}, {"mutates", true},
      {"inputSchema", kelpie::NativeExtensionInputSchema("play-script")}},
    {{"name", "kelpie_abort_script"}, {"method", "abort-script"}, {"mutates", true},
      {"inputSchema", kelpie::NativeExtensionInputSchema("abort-script")}}
  });
  const json config = {{"nativeMethods", {"play-script", "abort-script"}},
    {"extensions", extensions}, {"requireAuthorization", false}};
  auto rpc = [](std::string name, json body, bool generic) {
    if (generic) { body = {{"name", name}, {"arguments", body}}; name = "kelpie_extension"; }
    return json{{"jsonrpc", "2.0"}, {"id", 7}, {"method", "tools/call"},
      {"params", {{"name", name}, {"arguments", body}}}};
  };
  const json refused = {{"success", false}, {"error", {{"code", "SESSION_UNSUPPORTED"},
    {"message", "PRIVATE_NATIVE_MESSAGE"}}}};
  for (bool generic : {false, true}) {
    kelpie::BrowserGateway gateway(config);
    auto begin = [&](json body) {
      auto step = gateway.BeginMcp(rpc("kelpie_play_script", body, generic));
      assert(step["kind"] == "dispatch"); assert(step["method"] == "play-script");
    };
    auto error = [](const json& step) {
      assert(step["response"]["result"]["isError"] == true);
      assert(step.dump().find("PRIVATE_NATIVE_MESSAGE") == std::string::npos);
      return json::parse(step["response"]["result"]["content"][0]["text"].get<std::string>())["error"];
    };
    begin(script);
    auto result = error(gateway.Advance(refused));
    assert(result["code"] == "SESSION_UNSUPPORTED");
    assert(result["mayHaveCompleted"] == false);
    for (bool nested : {false, true}) {
      begin(script); auto uncertain = refused;
      if (nested) uncertain["error"]["mayHaveCompleted"] = true;
      else uncertain["mayHaveCompleted"] = true;
      result = error(gateway.Advance(uncertain));
      assert(result["code"] == "SESSION_UNSUPPORTED"); assert(result["mayHaveCompleted"] == true);
    }
    auto absent = script; absent.erase("sessionId"); begin(absent);
    result = error(gateway.Advance(refused));
    assert(result["code"] == "COMMAND_FAILED"); assert(result["mayHaveCompleted"] == true);
    begin(script);
    result = error(gateway.Advance({{"success", false}, {"error", {{"code", "TIMEOUT"}}}}));
    assert(result["code"] == "COMMAND_FAILED"); assert(result["mayHaveCompleted"] == true);
    begin(script);
    const auto cancelled = gateway.Cancel();
    assert(error(cancelled)["mayHaveCompleted"] == true);
    assert(gateway.Advance(refused) == cancelled);
    auto step = gateway.BeginMcp(rpc("kelpie_abort_script", {{"runId", "r"}}, generic));
    assert(step["kind"] == "dispatch");
    result = error(gateway.Advance(refused));
    assert(result["code"] == "COMMAND_FAILED"); assert(result["mayHaveCompleted"] == true);
  }
}
int main() {
  ScriptSessionPreflightErrors();
  ScriptRegistryForwarding();
  const kelpie::McpRegistry registry;
  for (const auto& tool : registry.all_tools()) {
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
  invalid = json::parse(R"({"rules":[{"pattern":"*","action":"mock","mockResponse":{"status":200,"headers":{"test":1},"body":""}}]})");
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
