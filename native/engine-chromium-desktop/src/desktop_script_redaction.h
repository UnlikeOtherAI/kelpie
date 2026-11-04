#pragma once
#include <nlohmann/json.hpp>
#include <string>
#include <vector>
namespace kelpie {
void RedactScriptOutputs(nlohmann::json& outputs,const nlohmann::json& actions,
                         const std::vector<std::string>& secrets);
}
