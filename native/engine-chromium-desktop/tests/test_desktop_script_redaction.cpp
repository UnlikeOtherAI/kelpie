#include "desktop_script_redaction.h"
#include <cassert>
#include <stdexcept>
using Json=nlohmann::json;
int main() {
  Json outputs={{"run","page run"}};
  kelpie::RedactScriptOutputs(outputs,Json::array(),{"run"});
  assert(outputs.at("[redacted]")=="page [redacted]");
  Json actions=Json::array({{{"action","extract"},{"name","cards"}}});
  outputs={{"cards",{{"fields",Json::array({{{"name","id"},{"status","ok"},
    {"values",Json::array({"id"})},{"provenance",{{"selector",".id"},{"source","text"},{"matches",1}}}}})},
    {"metadata",Json::array({{{"key","id"},{"value","id"},{"authority","publisher-claim"}}})},{"hash","id"}}}};
  kelpie::RedactScriptOutputs(outputs,actions,{"id","ok","text","publisher-claim"});
  const auto& cards=outputs.at("cards");
  assert(cards.at("fields").at(0).at("status")=="ok");
  assert(cards.at("fields").at(0).at("provenance").at("source")=="text");
  assert(cards.at("metadata").at(0).at("authority")=="publisher-claim");
  assert(cards.at("fields").at(0).at("name")=="[redacted]");
  assert(cards.at("hash")=="[redacted]");
  outputs={{"url","https://fixture/?value=a%20b%2B!"}};
  kelpie::RedactScriptOutputs(outputs,Json::array(),{"a b+!"});
  assert(outputs.at("url")=="https://fixture/?value=[redacted]");
  outputs={{"url","a+b%2B%21"}};
  kelpie::RedactScriptOutputs(outputs,Json::array(),{"a b+!"});
  assert(outputs.at("url")=="[redacted]");
  outputs={{"run","one"},{"error","two"}};
  bool collision=false;
  try { kelpie::RedactScriptOutputs(outputs,Json::array(),{"run","error"}); }
  catch(const std::runtime_error& error) { collision=std::string(error.what())=="OUTPUT_REDACTION_COLLISION"; }
  assert(collision);
  outputs={{"result","redacted e"}};
  kelpie::RedactScriptOutputs(outputs,Json::array(),{"e","redacted"});
  assert(outputs.at("r[redacted]sult")=="[redacted] [redacted]");
}
