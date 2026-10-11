#include "inference_service.h"
#include "inference_store.h"
#include <cassert>
#include <filesystem>
#include <fstream>
#include <future>

using namespace kelpie::windows;
using json = nlohmann::json;
int main() {
  assert(ParseInferenceURL(" HTTP://LOCALHOST:11434/v1/models ").base == "http://localhost:11434/v1");
  assert(ParseInferenceURL("http://[::1]:8080/v1").loopback);
  for (const auto* invalid : {"", "file:///tmp/model", "https://user:pass@example.com/v1", "https://host/v1?q=x", "http://host:0"}) {
    bool rejected = false;
    try { ParseInferenceURL(invalid); } catch (const InferenceError&) { rejected = true; }
    assert(rejected);
  }
  auto directory = std::filesystem::temp_directory_path() / NewInferenceId();
  std::filesystem::create_directories(directory);
  int calls = 0;
  json sent;
  bool fail = false;
  bool discovery = true;
  std::promise<void> entered, release;
  auto released = release.get_future().share();
  bool blocking = false;
  auto request = [&](const std::string& base, const std::string& op, const std::string& key, const json* body) -> json {
    ++calls; assert(base == "http://localhost:11434/v1"); assert(key == "test-secret");
    if (fail) throw InferenceError("ENDPOINT_UNREACHABLE", "Offline");
    if (op == "models") {
      if (!discovery) throw InferenceError("MODEL_DISCOVERY_UNSUPPORTED", "No model list");
      return {{"data", json::array({{{"id", "tiny"}}})}};
    }
    assert(body && body->at("model") == "tiny" && body->at("stream") == false);
    sent = *body;
    if (blocking) { entered.set_value(); released.wait(); }
    return {{"choices", json::array({{{"message", {{"content", "4"}}}, {"finish_reason", "stop"}}})}};
  };
  {
    InferenceService service(directory, request);
    auto saved = service.Execute("ai-endpoint-save", {{"name", "Local"}, {"baseURL", "http://localhost:11434"},
        {"model", "tiny"}, {"apiKey", "test-secret"}});
    assert(saved["success"] == true && calls == 0);
    assert(saved.dump().find("test-secret") == std::string::npos);
    auto loaded = service.Execute("ai-load", {{"backend", "openai"}, {"endpoint", "Local"}});
    assert(loaded["loaded"] == true);
    auto answer = service.Execute("ai-infer", {{"prompt", "2 + 2?"}, {"agent", false}});
    assert(answer["response"] == "4");
    kelpie::DesktopRouter router;
    service.Register(router);
    json snapshot = {{"success", true}, {"url", "https://second.test"}, {"title", "Second"},
        {"text", std::string(15000, 'x')}, {"accessibleLabels", json::array({"Kelpie logo", "Accessible SVG title"})}};
    router.Register("get-page-text", [&](const json& params) {
      assert(params.at("tabId") == "second" && params.at("generation") == 9);
      return snapshot;
    });
    json history = json::array();
    for (int index = 0; index < 15; ++index) {
      history.push_back({{"role", "user"}, {"content", "Remember " + std::to_string(index)}});
      history.push_back({{"role", "assistant"}, {"content", "Saved"}});
    }
    history.push_back({{"role", "user"}, {"content", "Which logo?"}});
    const json chat = {{"messages", history}, {"context", "page_text"}, {"tabId", "second"}, {"generation", 9}};
    assert(service.Execute("ai-infer", chat)["response"] == "4");
    assert(sent["messages"].size() == 31);
    assert(sent["messages"][0]["content"] == "Remember 0");
    const auto current = sent["messages"].back()["content"].get<std::string>();
    assert(current.find("Kelpie logo") != std::string::npos && current.find("Accessible SVG title") != std::string::npos);
    assert(current.find("https://second.test") != std::string::npos && current.find("textTruncated") != std::string::npos);
    const int before_error = calls;
    snapshot = {{"success", false}, {"error", {{"code", "TAB_NOT_FOUND"}, {"message", "Closed"}}}};
    assert(service.Execute("ai-infer", chat)["error"]["code"] == "TAB_NOT_FOUND");
    assert(calls == before_error);
    snapshot = {{"success", true}, {"text", "malformed snapshot"}};
    assert(service.Execute("ai-infer", chat)["error"]["code"] == "PAGE_CONTEXT_FAILED");
    assert(calls == before_error);
    snapshot = {{"success", true}, {"url", "about:blank"}, {"title", ""}, {"text", ""}, {"accessibleLabels", json::array()}};
    assert(service.Execute("ai-infer", chat)["response"] == "4");

    discovery = false;
    assert(service.Execute("ai-load", {{"backend", "openai"}, {"endpoint", "Local"}})["loaded"] == true);
    discovery = true;
    blocking = true;
    auto inference = std::async(std::launch::async, [&] { return service.Execute("ai-infer", {{"prompt", "wait"}}); });
    entered.get_future().wait();
    auto unload = std::async(std::launch::async, [&] { return service.Execute("ai-unload"); });
    assert(unload.wait_for(std::chrono::milliseconds(100)) == std::future_status::timeout);
    release.set_value();
    inference.get();
    assert(unload.get()["loaded"] == false);
    blocking = false;
    assert(service.Execute("ai-load", {{"backend", "openai"}, {"endpoint", "Local"}})["loaded"] == true);
    fail = true;
    assert(service.Execute("ai-infer", {{"prompt", "again"}})["error"]["code"] == "ENDPOINT_UNREACHABLE");
    assert(service.Execute("ai-status")["backend"] == "openai");
  }
  std::ifstream encrypted(directory / "inference.v1.dpapi", std::ios::binary);
  const std::string stored{std::istreambuf_iterator<char>(encrypted), {}};
  assert(stored.find("test-secret") == std::string::npos);
  encrypted.close();
  {
    InferenceService restored(directory, request);
    const auto state = restored.Execute("ai-endpoints");
    assert(state["endpoints"].size() == 1 && state["endpoints"][0]["hasApiKey"] == true);
    assert(restored.Execute("ai-status")["loaded"] == false); // no stale readiness after restart
    auto removed = restored.Execute("ai-endpoint-remove", {{"id", state["endpoints"][0]["id"]}});
    assert(removed["success"] == true);
    assert(restored.Execute("ai-status")["backend"] == "none");
  }
  std::filesystem::remove_all(directory);
}
