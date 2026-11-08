#pragma once
#include <filesystem>
#include <nlohmann/json.hpp>
namespace kelpie::windows {
nlohmann::json ReadInferenceStore(const std::filesystem::path& file);
void WriteInferenceStore(const std::filesystem::path& file, const nlohmann::json& data);
std::string NewInferenceId();
}
