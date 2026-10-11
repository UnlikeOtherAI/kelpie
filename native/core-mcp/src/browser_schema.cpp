#include "browser_schema.h"
#include <cmath>
#include <string>
#include <regex>
namespace kelpie {
namespace {
using json = nlohmann::json;
std::size_t Utf16Length(const std::string& text) {
  std::size_t length = 0;
  for (unsigned char byte : text) {
    if ((byte & 0xc0) != 0x80) length += (byte & 0xf8) == 0xf0 ? 2 : 1;
  }
  return length;
}
bool Validate(const json& root, const json& schema, json* value, int depth) {
  if (depth > 100 || !schema.is_object()) return false;
  if (schema.contains("$ref")) {
    const std::string ref = schema["$ref"].get<std::string>();
    if (ref.rfind("#/", 0) != 0) return false;
    return Validate(root, root.at(json::json_pointer(ref.substr(1))), value, depth + 1);
  }
  for (const char* union_key : {"anyOf", "oneOf"}) {
    if (!schema.contains(union_key)) continue;
    int matches = 0;
    json candidate;
    for (const auto& alternative : schema[union_key]) {
      auto copy = *value;
      if (Validate(root, alternative, &copy, depth + 1)) { ++matches; candidate = std::move(copy); }
    }
    if (matches == 0 || (std::string(union_key) == "oneOf" && matches != 1)) return false;
    *value = std::move(candidate);
  }
  if (schema.contains("const") && *value != schema["const"]) return false;
  if (schema.contains("enum")) {
    bool found = false;
    for (const auto& member : schema["enum"]) if (*value == member) found = true;
    if (!found) return false;
  }
  const std::string type = schema.value("type", std::string());
  if (type == "object" && !value->is_object()) return false;
  if (type == "array" && !value->is_array()) return false;
  if (type == "string" && !value->is_string()) return false;
  if (type == "boolean" && !value->is_boolean()) return false;
  if (type == "null" && !value->is_null()) return false;
  if ((type == "number" || type == "integer") && !value->is_number()) return false;
  if (value->is_number()) {
    double number = value->get<double>();
    if (!std::isfinite(number) || (type == "integer" && std::floor(number) != number)) return false;
    if (schema.contains("minimum") && number < schema["minimum"].get<double>()) return false;
    if (schema.contains("maximum") && number > schema["maximum"].get<double>()) return false;
    if (schema.contains("exclusiveMinimum") && number <= schema["exclusiveMinimum"].get<double>()) return false;
    if (schema.contains("exclusiveMaximum") && number >= schema["exclusiveMaximum"].get<double>()) return false;
  }
  if (value->is_string()) {
    const auto size = Utf16Length(value->get<std::string>());
    if (schema.contains("minLength") && size < schema["minLength"].get<std::size_t>()) return false;
    if (schema.contains("maxLength") && size > schema["maxLength"].get<std::size_t>()) return false;
    if (schema.contains("pattern") && !std::regex_search(value->get<std::string>(), std::regex(schema["pattern"].get<std::string>()))) return false;
  }
  if (value->is_array()) {
    if (schema.contains("minItems") && value->size() < schema["minItems"].get<std::size_t>()) return false;
    if (schema.contains("maxItems") && value->size() > schema["maxItems"].get<std::size_t>()) return false;
    if (schema.contains("items")) for (auto& item : *value) if (!Validate(root, schema["items"], &item, depth + 1)) return false;
  }
  if (value->is_object()) {
    const auto properties = schema.value("properties", json::object());
    for (auto it = value->begin(); it != value->end(); ++it) {
      if (schema.contains("propertyNames")) {
        json key = it.key();
        if (!Validate(root, schema["propertyNames"], &key, depth + 1)) return false;
      }
      if (properties.contains(it.key())) {
        if (!Validate(root, properties[it.key()], &it.value(), depth + 1)) return false;
      } else if (schema.contains("additionalProperties")) {
        const auto& extra = schema["additionalProperties"];
        if (extra == false || (extra.is_object() && !Validate(root, extra, &it.value(), depth + 1))) return false;
      }
    }
    for (auto it = properties.begin(); it != properties.end(); ++it) {
      const json* defaults = &it.value();
      int refs = 0;
      while (defaults->contains("$ref") && ++refs <= 100) {
        const std::string ref = (*defaults)["$ref"];
        if (ref.rfind("#/", 0) != 0) return false;
        defaults = &root.at(json::json_pointer(ref.substr(1)));
      }
      if (refs > 100) return false;
      if (!value->contains(it.key()) && defaults->contains("default")) (*value)[it.key()] = (*defaults)["default"];
    }
    for (const auto& key : schema.value("required", json::array())) if (!value->contains(key.get<std::string>())) return false;
  }
  return true;
}
}
bool ValidateBrowserJson(const json& schema, json* value) {
  try { return Validate(schema, schema, value, 0); } catch (...) { return false; }
}
}
