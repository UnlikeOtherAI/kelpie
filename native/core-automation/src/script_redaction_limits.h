#pragma once
#include <nlohmann/json.hpp>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>
namespace kelpie {
inline bool RedactionName(const std::string& name) {
 if(name.empty()||name.size()>64) return false;
 const auto alpha=[](char c){return (c>='A'&&c<='Z')||(c>='a'&&c<='z');};
 if(!alpha(name[0])) return false;
 for(char c:name) if(!alpha(c)&&!(c>='0'&&c<='9')&&c!='_') return false;
 return true;
}
inline void ValidateRedactionInputs(const std::vector<std::string>& names,const std::vector<std::string>& secrets) {
 if(names.size()>1000||secrets.size()>1000) throw std::runtime_error("OUTPUT_REDACTION_LIMIT");
 std::set<std::string> unique;
 for(const auto& name:names) if(!RedactionName(name)||!unique.insert(name).second)
   throw std::runtime_error("OUTPUT_REDACTION_INVALID");
 std::size_t bytes=0;
 for(const auto& secret:secrets) {
   if(secret.size()>65536||secret.size()>4194304-bytes) throw std::runtime_error("OUTPUT_REDACTION_LIMIT");
   bytes+=secret.size();
 }
}
inline void RedactionTree(const nlohmann::json& value,std::size_t depth,std::size_t& nodes,std::size_t& bytes) {
 if(depth>24||nodes==0) throw std::runtime_error("OUTPUT_REDACTION_LIMIT");
 --nodes;
 const auto consume=[&](std::size_t size) {
   if(size>bytes) throw std::runtime_error("OUTPUT_REDACTION_LIMIT"); bytes-=size;
 };
 consume(1);
 if(value.is_string()) consume(value.get_ref<const std::string&>().size());
 else if(value.is_array()) for(const auto& child:value) RedactionTree(child,depth+1,nodes,bytes);
 else if(value.is_object()) for(const auto& item:value.items()) {
   consume(item.key().size()); RedactionTree(item.value(),depth+1,nodes,bytes);
 }
 else if(!value.is_primitive()||value.is_binary()||value.is_discarded())
   throw std::runtime_error("OUTPUT_REDACTION_INVALID");
}
inline void ValidateRedactionTree(const nlohmann::json& outputs) {
 if(!outputs.is_object()) throw std::runtime_error("OUTPUT_REDACTION_INVALID");
 std::size_t nodes=32768,bytes=262144; RedactionTree(outputs,0,nodes,bytes);
}
}
