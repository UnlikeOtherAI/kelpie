#pragma once
#include <string_view>
#include <nlohmann/json.hpp>
namespace kelpie {
nlohmann::json NativeExtensionInputSchema(std::string_view endpoint);
bool NativeExtensionMutates(std::string_view endpoint);
}
