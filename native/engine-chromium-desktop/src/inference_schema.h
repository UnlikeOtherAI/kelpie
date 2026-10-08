#pragma once
#include <string_view>
#include <nlohmann/json.hpp>
namespace kelpie {
inline nlohmann::json InferenceInputSchema(std::string_view endpoint) {
  using json = nlohmann::json;
  json properties = json::object(), required = json::array();
  auto field = [&](const char* name, const char* type) { properties[name] = {{"type", type}}; };
  if (endpoint == "ai-load") {
    field("backend", "string"); field("model", "string"); field("endpoint", "string");
    properties["contextSize"] = {{"type", "integer"}, {"minimum", 256}, {"maximum", 8192}};
  } else if (endpoint == "ai-infer") {
    for (auto name : {"prompt", "text", "context", "tabId"}) field(name, "string");
    field("messages", "array"); field("agent", "boolean"); field("allowActions", "boolean");
    properties["maxTokens"] = {{"type", "integer"}, {"minimum", 1}, {"maximum", 8192}};
    properties["temperature"] = {{"type", "number"}, {"minimum", 0}, {"maximum", 2}};
  } else if (endpoint == "ai-endpoint-save") {
    for (auto name : {"id", "name", "baseURL", "model"}) field(name, "string");
    field("clearApiKey", "boolean"); required = {"name", "baseURL"};
  } else if (endpoint == "ai-endpoint-remove" || endpoint == "ai-endpoint-models" || endpoint == "ai-endpoint-test") {
    field("id", "string"); required = {"id"};
    if (endpoint == "ai-endpoint-test") { field("model", "string"); field("generate", "boolean"); field("tools", "boolean"); }
  } else if (endpoint == "ai-endpoint-health") { field("id", "string"); field("refresh", "boolean"); }
  return {{"type", "object"}, {"properties", properties}, {"required", required}, {"additionalProperties", false}};
}
}
