#include "kelpie/script_redaction.h"
#include "kelpie/script_redaction.hpp"
#include <cstdlib>
#include <cstring>
#include <new>
#include <stdexcept>
#include <string_view>
namespace {
constexpr std::size_t kWireLimit=5*1024*1024;
// Bound parser work/stack before JSON materialization. The parser subsequently
// checks full JSON syntax, escapes and UTF-8; this scanner only enforces limits.
std::string_view BoundedInput(const char* input) {
 if(!input) throw std::runtime_error("OUTPUT_REDACTION_INVALID");
 std::size_t length=0;
 while(length<=kWireLimit&&input[length]) ++length;
 if(length>kWireLimit) throw std::runtime_error("OUTPUT_REDACTION_LIMIT");
 bool quoted=false,escaped=false,primitive=false;
 std::size_t depth=0,tokens=0,string_bytes=0;
 for(std::size_t i=0;i<length;++i) {
   const char c=input[i];
   if(quoted) {
     if(++string_bytes>524288) throw std::runtime_error("OUTPUT_REDACTION_LIMIT");
     if(escaped) escaped=false;
     else if(c=='\\') escaped=true;
     else if(c=='"') quoted=false;
     continue;
   }
   const bool separator=c==' '||c=='\r'||c=='\n'||c=='\t'||c==','||c==':';
   if(c=='"') { quoted=true;string_bytes=0;primitive=false;++tokens; }
   else if(c=='{'||c=='[') {
     if(++depth>24) throw std::runtime_error("OUTPUT_REDACTION_LIMIT");
     primitive=false;++tokens;
   } else if(c=='}'||c==']') {
     if(!depth) throw std::runtime_error("OUTPUT_REDACTION_INVALID");
     --depth;primitive=false;++tokens;
   } else if(separator) primitive=false;
   else if(!primitive) { primitive=true;++tokens; }
   if(tokens>65536) throw std::runtime_error("OUTPUT_REDACTION_LIMIT");
 }
 if(quoted||depth) throw std::runtime_error("OUTPUT_REDACTION_INVALID");
 return {input,length};
}
char* Copy(const std::string& value) {
 auto* output=static_cast<char*>(std::malloc(value.size()+1));
 if(output) std::memcpy(output,value.c_str(),value.size()+1);
 return output;
}
char* Error(const char* code) noexcept {
 // Fixed errors never copy parser or page diagnostics.
 try { return Copy(std::string("{\"ok\":false,\"error\":{\"code\":\"")+code+"\"}}"); }
 catch(...) { return nullptr; }
}
}
extern "C" char* kelpie_script_redact_outputs_json(const char* input) {
 try {
   const auto wire=BoundedInput(input);
   auto body=nlohmann::json::parse(wire.begin(),wire.end());
   if(!body.is_object()||body.size()!=3||!body.contains("outputs")||
      !body.contains("extractionNames")||!body["extractionNames"].is_array()||
      !body.contains("secrets")||!body["secrets"].is_array())
     return Error("OUTPUT_REDACTION_INVALID");
   std::vector<std::string> names,secrets;
   if(body["extractionNames"].size()>1000||body["secrets"].size()>1000)
     return Error("OUTPUT_REDACTION_LIMIT");
   for(const auto& name:body["extractionNames"]) {
     if(!name.is_string()) return Error("OUTPUT_REDACTION_INVALID");
     names.push_back(name.get<std::string>());
   }
   for(const auto& secret:body["secrets"]) {
     if(!secret.is_string()) return Error("OUTPUT_REDACTION_INVALID");
     secrets.push_back(secret.get<std::string>());
   }
   kelpie::RedactNamedScriptOutputs(body["outputs"],names,secrets);
   const auto result=nlohmann::json({{"ok",true},{"outputs",std::move(body["outputs"])}}).dump();
   if(result.size()>262144+32) return Error("OUTPUT_REDACTION_LIMIT");
   return Copy(result);
 } catch(const std::bad_alloc&) { return nullptr; }
 catch(const std::runtime_error& error) {
   const std::string_view code(error.what());
   if(code=="OUTPUT_REDACTION_LIMIT"||code=="OUTPUT_REDACTION_COLLISION"||code=="OUTPUT_REDACTION_INVALID")
     return Error(error.what());
   return Error("OUTPUT_REDACTION_INVALID");
 } catch(...) { return Error("OUTPUT_REDACTION_INVALID"); }
}
extern "C" void kelpie_script_redaction_free_string(char* value) { std::free(value); }
