#include "desktop_script_redaction.h"
#include <algorithm>
#include <set>
#include <stdexcept>
#include <string_view>

namespace kelpie {
namespace {
using Json=nlohmann::json;
enum class Shape { dynamic,extraction,field,provenance,metadata,revision };
std::string Encoded(const std::string& value,bool form) {
  constexpr char hex[]="0123456789ABCDEF"; std::string result;
  for(unsigned char c:value) {
    const bool alpha=(c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9');
    if(alpha||c=='-'||c=='_'||c=='.'||c=='*'||(!form&&(c=='!'||c=='~'||c==39||c=='('||c==')'))) result.push_back(c);
    else if(form&&c==' ') result.push_back('+');
    else { result.push_back('%'); result.push_back(hex[c>>4]); result.push_back(hex[c&15]); }
  }
  return result;
}
struct Scrubber {
  struct Pattern { std::string text; bool encoded; };
  std::vector<Pattern> secrets;
  std::size_t comparisons=8000000, text_bytes=262144;
  explicit Scrubber(const std::vector<std::string>& values) {
    std::set<std::pair<std::string,bool>> unique;
    for(const auto& value:values) if(!value.empty()) {
      unique.emplace(value,false); unique.emplace(Encoded(value,false),true); unique.emplace(Encoded(value,true),true);
    }
    for(const auto& [text,encoded]:unique) secrets.push_back({text,encoded});
    std::sort(secrets.begin(),secrets.end(),[](const auto& a,const auto& b) {
      return a.text.size()!=b.text.size()?a.text.size()>b.text.size():a.text<b.text;
    });
  }
  static char HexCase(char value) {
    return value>='a'&&value<='f'?static_cast<char>(value-'a'+'A'):value;
  }
  std::string Text(const std::string& input) {
    std::string output;
    for(std::size_t at=0;at<input.size();) {
      std::size_t match=0;
      for(const auto& pattern:secrets) {
        const auto& secret=pattern.text;
        if(secret.size()>input.size()-at) continue;
        std::size_t length=0;
        for(;length<secret.size();++length) {
          if(!comparisons--) throw std::runtime_error("OUTPUT_REDACTION_LIMIT");
          const bool hex=pattern.encoded && ((length>=1&&secret[length-1]=='%') || (length>=2&&secret[length-2]=='%'));
          if(hex?HexCase(input[at+length])!=secret[length]:input[at+length]!=secret[length]) break;
        }
        if(length==secret.size()) { match=length; break; }
      }
      const std::string_view piece=match?std::string_view("[redacted]"):std::string_view(input.data()+at,1);
      if(piece.size()>text_bytes) throw std::runtime_error("OUTPUT_REDACTION_LIMIT");
      text_bytes-=piece.size(); output.append(piece); at+=match?match:1;
    }
    return output;
  }
  static bool Known(Shape shape,const std::string& key) {
    switch(shape) {
      case Shape::extraction:return key=="url"||key=="documentRevision"||key=="fields"||key=="metadata"||key=="truncated";
      case Shape::field:return key=="name"||key=="status"||key=="values"||key=="records"||key=="provenance";
      case Shape::provenance:return key=="selector"||key=="source"||key=="matches"||key=="matchesLimited";
      case Shape::metadata:return key=="key"||key=="value"||key=="selector"||key=="attribute"||key=="authority"||key=="provenanceComplete"||key=="index";
      case Shape::revision:return key=="availability";
      default:return false;
    }
  }
  static bool Trusted(Shape shape,const std::string& key,const Json& value) {
    if(shape==Shape::extraction&&key=="truncated") return value.is_boolean();
    if(shape==Shape::field&&key=="status") return value=="ok"||value=="missing"||value=="ambiguous"||value=="incomplete";
    if(shape==Shape::provenance&&key=="source") return value=="text"||value=="href"||value=="src"||value=="datetime";
    if(shape==Shape::provenance&&key=="matches") return value.is_number_integer();
    if(shape==Shape::provenance&&key=="matchesLimited") return value.is_boolean();
    if(shape==Shape::metadata&&key=="authority") return value=="publisher-claim";
    if(shape==Shape::revision&&key=="availability") return value=="unavailable";
    return false;
  }
  static Shape Child(Shape shape,const std::string& key) {
    if(shape==Shape::extraction) {
      if(key=="fields") return Shape::field;
      if(key=="metadata") return Shape::metadata;
      if(key=="documentRevision") return Shape::revision;
    }
    if(shape==Shape::field) {
      if(key=="records") return Shape::field;
      if(key=="provenance") return Shape::provenance;
    }
    return Shape::dynamic;
  }
  Json Value(const Json& value,Shape shape) {
    if(value.is_string()) return Text(value.get_ref<const std::string&>());
    if(value.is_array()) {
      Json output=Json::array();
      for(const auto& child:value) output.push_back(Value(child,shape));
      return output;
    }
    if(!value.is_object()) return value;
    Json output=Json::object();
    for(const auto& item:value.items()) {
      const auto key=Known(shape,item.key())?item.key():Text(item.key());
      if(output.contains(key)) throw std::runtime_error("OUTPUT_REDACTION_COLLISION");
      output[key]=Trusted(shape,item.key(),item.value())?item.value():Value(item.value(),Child(shape,item.key()));
    }
    return output;
  }
};
}
void RedactScriptOutputs(Json& outputs,const Json& actions,const std::vector<std::string>& secrets) {
  if(secrets.empty()) return;
  Scrubber scrubber(secrets);
  Json safe=Json::object();
  for(const auto& item:outputs.items()) {
    const auto name=scrubber.Text(item.key());
    if(safe.contains(name)) throw std::runtime_error("OUTPUT_REDACTION_COLLISION");
    const bool extraction=std::any_of(actions.begin(),actions.end(),[&](const Json& action) {
      return action.value("action",std::string())=="extract" && action.value("name",std::string())==item.key();
    });
    safe[name]=scrubber.Value(item.value(),extraction?Shape::extraction:Shape::dynamic);
  }
  if(safe.dump().size()>262144) throw std::runtime_error("OUTPUT_REDACTION_LIMIT");
  outputs=std::move(safe);
}
}
