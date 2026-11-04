#include "desktop_script_redaction.h"
#include "kelpie/script_redaction.hpp"
namespace kelpie {
void RedactScriptOutputs(nlohmann::json& outputs,const nlohmann::json& actions,
 const std::vector<std::string>& secrets) {
 std::vector<std::string> names;
 for(const auto& action:actions) if(action.value("action",std::string())=="extract")
   names.push_back(action.value("name",std::string()));
 RedactNamedScriptOutputs(outputs,names,secrets);
}
}
