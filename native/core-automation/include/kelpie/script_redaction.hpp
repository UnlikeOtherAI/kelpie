#pragma once
#include <nlohmann/json.hpp>
#include <string>
#include <vector>
namespace kelpie {
// Strong exception guarantee: outputs change only after complete successful scrub.
void RedactNamedScriptOutputs(nlohmann::json& outputs,
 const std::vector<std::string>& extraction_names,const std::vector<std::string>& secrets);
}
