#include "kelpie/script_redaction.hpp"
#include "kelpie/script_redaction.h"
#include <cassert>
#include <stdexcept>
using Json=nlohmann::json;
void MatchVectors() {
  Json outputs={{"run","page run"}};
  kelpie::RedactNamedScriptOutputs(outputs,{},{"run"});
  assert(outputs.at("[redacted]")=="page [redacted]");
  outputs={{"cards",{{"fields",Json::array({{{"name","id"},{"status","ok"},
    {"values",Json::array({"id"})},{"provenance",{{"selector",".id"},{"source","text"},{"matches",1}}}}})},
    {"metadata",Json::array({{{"key","id"},{"value","id"},{"authority","publisher-claim"}}})},{"hash","id"}}}};
  kelpie::RedactNamedScriptOutputs(outputs,{"cards"},{"id","ok","text","publisher-claim"});
  const auto& cards=outputs.at("cards");
  assert(cards.at("fields").at(0).at("status")=="ok");
  assert(cards.at("fields").at(0).at("provenance").at("source")=="text");
  assert(cards.at("metadata").at(0).at("authority")=="publisher-claim");
  assert(cards.at("fields").at(0).at("name")=="[redacted]");
  assert(cards.at("hash")=="[redacted]");
  outputs={{"url","https://fixture/?value=a%20b%2B!"}};
  kelpie::RedactNamedScriptOutputs(outputs,{},{"a b+!"});
  assert(outputs.at("url")=="https://fixture/?value=[redacted]");
  outputs={{"url","a+b%2B%21"}};
  kelpie::RedactNamedScriptOutputs(outputs,{},{"a b+!"});
  assert(outputs.at("url")=="[redacted]");
  outputs={{"run","one"},{"error","two"}};
  bool collision=false;
  try { kelpie::RedactNamedScriptOutputs(outputs,{},{"run","error"}); }
  catch(const std::runtime_error& error) { collision=std::string(error.what())=="OUTPUT_REDACTION_COLLISION"; }
  assert(collision);
  outputs={{"result","redacted e"}};
  kelpie::RedactNamedScriptOutputs(outputs,{},{"e","redacted"});
  assert(outputs.at("r[redacted]sult")=="[redacted] [redacted]");

  const auto scrub=[](const std::string& input,const std::string& secret) {
    Json value={{"value",input}}; kelpie::RedactNamedScriptOutputs(value,{},{secret});
    return value.at("value").get<std::string>();
  };
  for(const auto& encoded:{"Aa%20b%2b!","Aa+b%2b%21","Aa%20b%2B!"})
    assert(scrub(encoded,"Aa b+!")=="[redacted]");
  assert(scrub("aa b+!","Aa b+!")=="aa b+!");
  assert(scrub("Aa%20B%2b!","Aa b+!")=="Aa%20B%2b!");
  assert(scrub("token%2FValue","token%2FValue")=="[redacted]");
  assert(scrub("token%252FValue","token%2FValue")=="[redacted]");
  assert(scrub("token%2fValue","token%2FValue")=="token%2fValue");
}

void AbiVectors();
int main() { MatchVectors(); AbiVectors(); }

namespace {
Json Call(const std::string& text) {
 char* raw=kelpie_script_redact_outputs_json(text.c_str()); assert(raw);
 const auto result=Json::parse(raw); kelpie_script_redaction_free_string(raw); return result;
}
Json Envelope(Json outputs,Json names=Json::array(),Json secrets=Json::array()) {
 return {{"outputs",outputs},{"extractionNames",names},{"secrets",secrets}};
}
void Refused(const std::string& text,const char* code) {
 auto result=Call(text); assert(result["ok"]==false); assert(result["error"]["code"]==code);
 assert(result.dump().find("SYNTHETIC_PRIVATE")==std::string::npos);
}
}
void AbiVectors() {
 auto request=Envelope({{"value",{{"nested",Json::array({"Aa%20b%2b!","visible"})}}}},
   Json::array(),{"Aa b+!"}).dump();
 const auto result=Call(request);
 assert(result["ok"]==true);
 assert(result["outputs"]["value"]["nested"][0]=="[redacted]");
 // Independently allocated strings remain valid until the caller frees each one.
 char* first=kelpie_script_redact_outputs_json(request.c_str());
 char* second=kelpie_script_redact_outputs_json(request.c_str());
 assert(first&&second&&first!=second); assert(std::string(first)==second);
 kelpie_script_redaction_free_string(second); assert(Json::parse(first)["ok"]==true);
 kelpie_script_redaction_free_string(first); kelpie_script_redaction_free_string(nullptr);
 char* empty=kelpie_script_redact_outputs_json(nullptr); assert(empty);
 assert(Json::parse(empty)["ok"]==false); kelpie_script_redaction_free_string(empty);
 Refused("{bad SYNTHETIC_PRIVATE","OUTPUT_REDACTION_INVALID");
 Refused(Envelope({{"value","x"}},{"bad-name"}).dump(),"OUTPUT_REDACTION_INVALID");
 Refused(Envelope({{"value","x"}},{"same","same"}).dump(),"OUTPUT_REDACTION_INVALID");
 Refused(Envelope({{"value","x"}},Json::array(),{123}).dump(),"OUTPUT_REDACTION_INVALID");
 Refused(Envelope({{"a",1},{"b",2}},Json::array(),{"a","b"}).dump(),"OUTPUT_REDACTION_COLLISION");
 Refused(std::string(5*1024*1024+1,' '),"OUTPUT_REDACTION_LIMIT");
 Refused(std::string(25,'[')+std::string(25,']'),"OUTPUT_REDACTION_LIMIT");
 Refused(Envelope({{"value",std::string(524289,'x')}}).dump(),"OUTPUT_REDACTION_LIMIT");
 Json aggregate=Json::array(); for(int i=0;i<65;++i) aggregate.push_back(std::string(65536,'x'));
 Refused(Envelope({{"value","x"}},Json::array(),aggregate).dump(),"OUTPUT_REDACTION_LIMIT");
 Refused(Envelope({{"value",std::string(262144,'x')}}).dump(),"OUTPUT_REDACTION_LIMIT");
 Refused(Envelope({{"value","x"}},Json::array(),{std::string(65537,'x')}).dump(),"OUTPUT_REDACTION_LIMIT");
 std::string bad=Envelope({{"value","SYNTHETIC_PRIVATE"}}).dump();
 bad.insert(bad.find("SYNTHETIC_PRIVATE"),1,static_cast<char>(0xff));
 Refused(bad,"OUTPUT_REDACTION_INVALID");
 Json many=Json::array(); for(int i=0;i<33000;++i) many.push_back(0);
 Refused(Envelope({{"value",many}}).dump(),"OUTPUT_REDACTION_LIMIT");
 // A short secret can expand greatly; byte and comparison budgets fail closed.
 Refused(Envelope({{"value",std::string(30000,'e')}},Json::array(),{"e"}).dump(),"OUTPUT_REDACTION_LIMIT");
 assert(Call(Envelope({{"unicode","příliš 😀"}},Json::array(),{"příliš"}).dump())["outputs"]["unicode"]=="[redacted] 😀");
 // Every attempted pattern consumes work even when it is longer than the remainder.
 Json long_secrets=Json::array();
 for(int i=0;i<1000;++i) long_secrets.push_back(std::string(100,'z')+std::to_string(i));
 Refused(Envelope({{"value",std::string(20000,'x')}},Json::array(),long_secrets).dump(),"OUTPUT_REDACTION_LIMIT");
 // Supported maximum field count remains ordinary data within the shared bounds.
 Json fields=Json::array();
 for(int i=0;i<512;++i) fields.push_back({{"name","field"},{"status","ok"},{"values",{"data"}},
   {"provenance",{{"selector","h2"},{"source","text"},{"matches",1}}}});
 assert(Call(Envelope({{"cards",{{"fields",fields},{"truncated",false}}}},{"cards"},{"ok"}).dump())["ok"]==true);
}
