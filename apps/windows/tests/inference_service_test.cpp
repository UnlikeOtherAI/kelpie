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
  bool expect_context = false;
  auto request = [&](const std::string& base, const std::string& op, const std::string& key, const json* body) -> json {
    ++calls; assert(base == "http://localhost:11434/v1"); assert(key == "test-secret");
    if (fail) throw InferenceError("ENDPOINT_UNREACHABLE", "Offline");
    if (op == "models") {
      if (!discovery) throw InferenceError("MODEL_DISCOVERY_UNSUPPORTED", "No model list");
      return {{"data", json::array({{{"id", "tiny"}}})}};
    }
    assert(body && body->at("model") == "tiny" && body->at("stream") == false);
    if (expect_context) assert(body->at("messages").dump().find("bounded snapshot") != std::string::npos);
    sent = *body;
    if (blocking) { entered.set_value(); released.wait(); }
    return {{"choices", json::array({{{"message", {{"content", "4"}}}, {"finish_reason", "stop"}}})}};
  };
  {
    InferenceService service(directory, request);
    kelpie::DesktopRouter router;
    router.Register("get-tabs", [](const json&) { return json{{"success", true}, {"tabs", {{{"id", "visible"}, {"active", true}}}}}; });
    router.Register("browser-control", [](const json& input) {
      assert(input["method"] == "tab.snapshot" && input["tabId"] == "visible" && input["params"]["maxChars"] == 12000);
      return json{{"version", 1}, {"ok", true}, {"value", {{"text", "bounded snapshot"}, {"title", "Fixture"}, {"url", "https://fixture.test"}, {"truncated", false}, {"elements", json::array()}}}};
    });
    service.Register(router);
    auto saved = service.Execute("ai-endpoint-save", {{"name", "Local"}, {"baseURL", "http://localhost:11434"},
        {"model", "tiny"}, {"apiKey", "test-secret"}});
    assert(saved["success"] == true && calls == 0);
    assert(saved.dump().find("test-secret") == std::string::npos);
    auto loaded = service.Execute("ai-load", {{"backend", "openai"}, {"endpoint", "Local"}});
    assert(loaded["loaded"] == true);
    auto answer = service.Execute("ai-infer", {{"prompt", "2 + 2?"}, {"agent", false}});
    assert(answer["response"] == "4");
    router.Register("get-current-url", [](const json&) { return json{{"success", true}}; });
    expect_context = true;
    assert(service.Execute("ai-infer", {{"prompt", "Read page"}, {"context", "dom"}})["response"] == "4");
    expect_context = false;
    assert(service.Execute("ai-infer", {{"prompt", "Act"}, {"agent", true}})["error"]["code"] == "TOOLS_NOT_SUPPORTED");
    bool stale_generation = false;
    int ownership_checks = 0;
    bool closes_during_snapshot = false;
    router.Register("get-current-url", [&](const json& params) {
      ++ownership_checks;
      if (params.value("tabId", "") == "second") assert(params.at("generation") == 9);
      return stale_generation ? json{{"success", false}, {"error", {{"code", "TAB_NOT_FOUND"}}}} : json{{"success", true}};
    });
    json snapshot = {{"version", 1}, {"ok", true}, {"value", {{"url", "https://second.test"}, {"title", "Second"},
        {"text", std::string(12000, 'x')}, {"truncated", true}, {"elements", json::array({
          {{"ref", "image1"}, {"role", "img"}, {"name", "Kelpie logo"}},
          {{"ref", "image2"}, {"role", "img"}, {"name", "Accessible SVG title"}}})}}}};
    router.Register("browser-control", [&](const json& input) {
      assert(input.at("tabId") == "second" && input.at("method") == "tab.snapshot");
      assert(!input.contains("generation") && input.at("params").at("maxChars") == 12000);
      if (closes_during_snapshot) stale_generation = true;
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
    assert(current.find("https://second.test") != std::string::npos && current.find("truncated") != std::string::npos);
    const int before_error = calls;
    snapshot = {{"version", 1}, {"ok", false}, {"error", {{"code", "TAB_NOT_FOUND"}, {"message", "Closed"}}}};
    assert(service.Execute("ai-infer", chat)["error"]["code"] == "TAB_NOT_FOUND");
    assert(calls == before_error);
    snapshot = {{"version", 1}, {"ok", true}, {"value", {{"text", "malformed snapshot"}}}};
    assert(service.Execute("ai-infer", chat)["error"]["code"] == "PAGE_CONTEXT_FAILED");
    assert(calls == before_error);
    snapshot = {{"version", 1}, {"ok", true}, {"value", {{"url", "about:blank"}, {"title", ""}, {"text", ""}, {"truncated", false}, {"elements", json::array()}}}};
    assert(service.Execute("ai-infer", chat)["response"] == "4");
    const int before_stale = calls;
    stale_generation = true;
    assert(service.Execute("ai-infer", chat)["error"]["code"] == "TAB_NOT_FOUND");
    assert(calls == before_stale && ownership_checks >= 2);
    stale_generation = false;
    closes_during_snapshot = true;
    const int before_snapshot_close = calls;
    const int before_checks = ownership_checks;
    assert(service.Execute("ai-infer", chat)["error"]["code"] == "TAB_NOT_FOUND");
    assert(calls == before_snapshot_close && ownership_checks == before_checks + 2);
    stale_generation = false;
    closes_during_snapshot = false;

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
    auto owner = std::make_shared<std::atomic<bool>>(false);
    auto stale = std::make_shared<std::atomic<bool>>(false);
    assert(!service.CancelOwned(owner)); // An idle connection does not own page chat.
    const int before_native = calls;
    assert(service.ExecuteOwned("ai-infer", {{"prompt", "native only"}}, owner, true)["error"]["code"] == "NO_MODEL_LOADED");
    assert(calls == before_native); // A changed backend cannot redirect extraction to the cloud.
    assert(service.ExecuteOwned("ai-cancel", json::object(), owner)["error"]["code"] == "INVALID_PARAM");
    const auto start_blocked = [&](InferenceService::Owner token) {
      entered = std::promise<void>(); release = std::promise<void>(); released = release.get_future().share();
      blocking = true;
      auto work = std::async(std::launch::async, [&,token] {
        return service.ExecuteOwned("ai-infer", {{"prompt", "wait"}}, token);
      });
      entered.get_future().wait();
      return work;
    };
    auto person_chat = start_blocked({});
    assert(!service.CancelOwned(owner));
    assert(service.ExecuteOwned("ai-infer", {{"prompt", "busy"}}, owner)["error"]["code"] == "AI_BUSY");
    assert(!service.CancelOwned(owner)); // A rejected request never steals ownership.
    release.set_value(); assert(person_chat.get()["response"] == "4");
    auto owned = start_blocked(owner);
    assert(!service.CancelOwned(stale));
    assert(service.CancelOwned(owner));
    release.set_value(); assert(owned.get()["error"]["code"] == "INFERENCE_CANCELLED");
    assert(!service.CancelOwned(owner)); // Completion retires its cancellation identity.
    auto later_chat = start_blocked({});
    assert(!service.CancelOwned(owner));
    release.set_value(); assert(later_chat.get()["response"] == "4");
    blocking = false;
    owner->store(true);
    const int before_cancelled = calls;
    assert(service.ExecuteOwned("ai-infer", {{"prompt", "stopped"}}, owner)["error"]["code"] == "INFERENCE_CANCELLED");
    assert(calls == before_cancelled);
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
  const auto model=directory/"downloaded.gguf";std::ofstream(model)<<"installed model placeholder";
  auto savedSettings=ReadInferenceStore(directory/"inference.v1.dpapi");savedSettings["localModel"]=model.string();savedSettings["backend"]="none";
  WriteInferenceStore(directory/"inference.v1.dpapi",savedSettings);
  { InferenceService restored(directory,request);const auto status=restored.Execute("ai-status");assert(status["modelInstalled"]==true && status["loaded"]==false); }
  std::filesystem::remove(model);
  { InferenceService restored(directory,request);assert(restored.Execute("ai-status")["modelInstalled"]==false); }
  std::filesystem::remove_all(directory);
}
