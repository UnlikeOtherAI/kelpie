#include "inference_service.h"
#include "inference_store.h"
#include <windows.h>
#include <chrono>

namespace kelpie::windows {
using json = nlohmann::json;
namespace {
json Success(json data) { data["success"] = true; return data; }
json Failure(const std::string& code, const std::string& message) {
  return {{"success", false}, {"error", {{"code", code}, {"message", message}}}};
}
int64_t Now() { return std::chrono::duration_cast<std::chrono::seconds>(std::chrono::system_clock::now().time_since_epoch()).count(); }
}
InferenceService::InferenceService(std::filesystem::path profile, Request request)
    : store_(std::move(profile) / "inference.v1.dpapi"), settings_(ReadInferenceStore(store_)), request_(std::move(request)) {
  if (!request_) request_ = [this](const auto& base, const auto& op, const auto& key, const json* body) {
    return transport_.Request(base, op, key, body);
  };
}
void InferenceService::Register(DesktopRouter& router) {
  router_ = &router;
  for (const auto* method : {"ai-status", "ai-load", "ai-unload", "ai-infer", "ai-cancel", "ai-endpoints",
      "ai-endpoint-save", "ai-endpoint-remove", "ai-endpoint-models", "ai-endpoint-test", "ai-endpoint-health"})
    router.Register(method, [this, method](const json& body) { return Execute(method, body); });
}
void InferenceService::Cancel() { cancelled_ = true; local_.Cancel(); transport_.Cancel(); }
json InferenceService::Execute(const std::string& method, const json& body) {
  if (method == "ai-cancel") { cancelled_ = true; local_.Cancel(); return Success({{"cancelled", transport_.Cancel()}}); }
  std::unique_lock lock(mutex_, std::try_to_lock);
  if (!lock.owns_lock()) return Failure("AI_BUSY", "Inference is busy; cancel it or wait for completion");
  try { cancelled_ = false; return Dispatch(method, body); }
  catch (const InferenceError& error) { return Failure(error.code, error.what()); }
  catch (const json::exception&) { return Failure("INVALID_PARAM", "Invalid inference parameters or model response"); }
  catch (const std::exception&) { return Failure("AI_INFERENCE_FAILED", "Inference operation failed"); }
}
void InferenceService::Persist() { WriteInferenceStore(store_, settings_); }
json& InferenceService::Endpoint(const std::string& id) {
  for (auto& endpoint : settings_["endpoints"])
    if (endpoint.value("id", "") == id || endpoint.value("name", "") == id) return endpoint;
  throw InferenceError("ENDPOINT_NOT_FOUND", "Select a saved inference endpoint");
}
json InferenceService::Public(const json& endpoint) {
  auto result = endpoint;
  result["hasApiKey"] = !result.value("apiKey", "").empty(); result.erase("apiKey");
  result["loopback"] = ParseInferenceURL(result.at("baseURL")).loopback;
  auto health = health_.find(endpoint.at("id"));
  result["health"] = health == health_.end() ? json{{"state", "unknown"}, {"online", false}, {"stale", true}} : health->second;
  if (health != health_.end() && Now() - health->second.value("checkedAt", int64_t(0)) > 90)
    result["health"] = {{"state", "unknown"}, {"online", false}, {"stale", true}};
  return result;
}
json InferenceService::Save(const json& body) {
  const auto name = body.at("name").get<std::string>();
  if (name.empty() || name.size() > 128) throw InferenceError("INVALID_PARAM", "Endpoint name must be 1 through 128 characters");
  const auto url = ParseInferenceURL(body.at("baseURL"));
  const auto id = body.value("id", NewInferenceId());
  json saved = {{"id", id}, {"name", name}, {"baseURL", url.base}, {"model", body.value("model", "")}, {"apiKey", ""}};
  for (const auto& endpoint : settings_["endpoints"]) {
    if (endpoint["id"] == id) saved = endpoint;
    else if (endpoint["name"] == name) throw InferenceError("INVALID_PARAM", "Endpoint names must be unique");
  }
  saved["name"] = name; saved["baseURL"] = url.base;
  if (body.contains("model")) saved["model"] = body.at("model").get<std::string>();
  if (body.contains("apiKey")) saved["apiKey"] = body.at("apiKey").get<std::string>();
  if (body.value("clearApiKey", false)) saved["apiKey"] = "";
  if (saved["apiKey"].get<std::string>().find_first_of("\r\n") != std::string::npos)
    throw InferenceError("INVALID_PARAM", "Invalid API key");
  if (body.contains("capabilities")) saved["capabilities"] = body.at("capabilities");
  bool updated = false;
  for (auto& endpoint : settings_["endpoints"]) if (endpoint["id"] == id) { endpoint = saved; updated = true; }
  if (!updated) settings_["endpoints"].push_back(saved);
  health_.erase(id); Persist();
  return Success({{"endpoint", Public(saved)}});
}
json InferenceService::Models(json& endpoint) {
  auto response = request_(endpoint.at("baseURL"), "models", endpoint.value("apiKey", ""), nullptr);
  auto entries = response.value("data", response.value("models", json()));
  if (!entries.is_array()) throw InferenceError("ENDPOINT_MALFORMED_RESPONSE", "Server returned no model list");
  json models = json::array();
  for (const auto& entry : entries) if (entry.is_object() && entry.value("id", json()).is_string())
    models.push_back({{"id", entry["id"]}});
  endpoint["models"] = models;
  return models;
}
json InferenceService::Probe(json& endpoint, bool generate) {
  json models = json::array();
  const auto id = endpoint.at("id").get<std::string>();
  json health = {{"checkedAt", Now()}, {"stale", false}, {"online", true}, {"state", "no_model"}};
  try {
    bool listed = false;
    try {
      models = Models(endpoint);
      for (const auto& model : models) if (model["id"] == endpoint.value("model", "")) listed = true;
    } catch (const InferenceError& error) {
      if (error.code != "MODEL_DISCOVERY_UNSUPPORTED") throw;
      health["discoveryUnsupported"] = true;
    }
    const auto model = endpoint.value("model", "");
    if (!model.empty()) health["state"] = listed ? "ready" : "model_missing";
    json result = {{"models", models}};
    if (generate && !model.empty()) {
      auto reply = Chat(endpoint, json::array({{{"role", "user"}, {"content", "Reply with OK."}}}), {{"maxTokens", 16}});
      if (!reply.value("content", json()).is_string()) throw InferenceError("ENDPOINT_MALFORMED_RESPONSE", "No generation text returned");
      result["generation"] = {{"ok", true}, {"text", reply["content"]}}; health["state"] = "ready";
    }
    health_[id] = health; result["health"] = health; return Success(result);
  } catch (const InferenceError& error) {
    health["state"] = error.code == "ENDPOINT_AUTH_FAILED" ? "auth_failed" : error.code == "ENDPOINT_LOADING" ? "loading" : "unreachable";
    health["online"] = error.code == "ENDPOINT_LOADING"; health_[id] = health; throw;
  }
}
json InferenceService::Status() {
  const auto backend = settings_.value("backend", "none");
  if (backend == "native") return local_.Execute("status", json::object());
  if (backend != "openai") return Success({{"backend", "none"}, {"loaded", false}, {"capabilities", json::array()}});
  auto endpoint = Public(Endpoint(settings_.value("activeEndpointId", "")));
  return Success({{"backend", "openai"}, {"model", endpoint.value("model", "")}, {"endpoint", endpoint},
      {"health", endpoint["health"]}, {"loaded", endpoint["health"].value("state", "unknown") == "ready"},
      {"capabilities", json::array({"text"})}});
}
json InferenceService::Dispatch(const std::string& method, const json& body) {
  if (method == "ai-status") return Status();
  if (method == "ai-endpoints") {
    json endpoints = json::array(); for (const auto& endpoint : settings_["endpoints"]) endpoints.push_back(Public(endpoint));
    return Success({{"endpoints", endpoints}, {"activeEndpointId", settings_.value("activeEndpointId", "")},
        {"executionHost", {{"platform", "windows"}, {"loopbackMeans", "this Windows computer"}}}});
  }
  if (method == "ai-endpoint-save") return Save(body);
  if (method == "ai-endpoint-remove") {
    const auto id = Endpoint(body.at("id")).at("id");
    auto& endpoints = settings_["endpoints"];
    endpoints.erase(std::remove_if(endpoints.begin(), endpoints.end(), [&](const json& entry) { return entry["id"] == id; }), endpoints.end());
    if (settings_.value("activeEndpointId", json()) == id) { settings_["backend"] = "none"; settings_.erase("activeEndpointId"); }
    Persist(); return Success({{"removed", true}});
  }
  if (method == "ai-endpoint-models") return Success({{"models", Models(Endpoint(body.at("id")))}});
  if (method == "ai-endpoint-test") {
    auto endpoint = Endpoint(body.at("id"));
    if (body.contains("model")) endpoint["model"] = body["model"];
    if (body.value("tools", false)) throw InferenceError("TOOLS_NOT_SUPPORTED", "Use plain text inference on Windows in this release");
    return Probe(endpoint, body.value("generate", true));
  }
  if (method == "ai-endpoint-health") {
    auto& endpoint = Endpoint(body.value("id", settings_.value("activeEndpointId", "")));
    if (body.value("refresh", false)) return Probe(endpoint, false);
    return Success({{"health", Public(endpoint)["health"]}});
  }
  if (method == "ai-unload") {
    local_.Cancel(); auto result = local_.Execute("unload", json::object());
    if (!result.value("success", false)) return result;
    settings_["backend"] = "none"; settings_.erase("activeEndpointId"); Persist(); return Status();
  }
  if (method == "ai-load") {
    const auto backend = body.value("backend", "native");
    if (backend == "native") {
      const auto path = std::filesystem::u8path(body.at("model").get<std::string>());
      MEMORYSTATUSEX memory{}; memory.dwLength = sizeof(memory); GlobalMemoryStatusEx(&memory);
      if (std::filesystem::exists(path) && std::filesystem::file_size(path) * 3 / 2 + 256ull * 1024 * 1024 > memory.ullAvailPhys)
        throw InferenceError("MODEL_MEMORY_LIMIT", "Use a smaller GGUF or a LAN inference endpoint");
      auto result = local_.Execute("load", body);
      if (result.value("success", false)) { settings_["backend"] = "native"; settings_["localModel"] = body["model"]; Persist(); }
      return result;
    }
    if (backend != "openai") throw InferenceError("INVALID_PARAM", "Choose native or openai backend");
    auto endpoint = Endpoint(body.at("endpoint"));
    if (body.contains("model")) endpoint["model"] = body.at("model").get<std::string>();
    if (endpoint.value("model", "").empty()) throw InferenceError("NO_MODEL_SELECTED", "Select a model ID first");
    auto health = Probe(endpoint, false);
    if (health["health"].value("discoveryUnsupported", false)) health = Probe(endpoint, true);
    if (health["health"]["state"] != "ready") throw InferenceError("MODEL_NOT_AVAILABLE", "Select a listed model or test generation first");
    Endpoint(endpoint.at("id")) = endpoint;
    settings_["activeEndpointId"] = endpoint.at("id"); settings_["backend"] = "openai"; Persist();
    local_.Execute("unload", json::object());
    return Status();
  }
  if (method == "ai-infer") return Infer(body);
  throw InferenceError("INVALID_PARAM", "Unknown inference operation");
}
}
