#pragma once
#include <nlohmann/json.hpp>
namespace kelpie {
// Validate and apply defaults from the generated authoritative schema. Never echo input in errors.
bool ValidateBrowserJson(const nlohmann::json& schema, nlohmann::json* value);
}
