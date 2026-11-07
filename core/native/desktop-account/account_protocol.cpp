#include "account_protocol.h"
#ifdef _WIN32
#include <windows.h>
#include <bcrypt.h>
#else
#include <openssl/evp.h>
#include <openssl/rand.h>
#endif
#include <algorithm>
#include <array>
#include <cctype>
#include <cstdio>
#include "kelpie/bookmark_store.h"

namespace kelpie::account {
namespace {
std::string Base64URL(const unsigned char* data, std::size_t size) {
  constexpr char alphabet[]="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
  std::string result; unsigned value=0; int bits=0;
  for (std::size_t i=0;i<size;++i) {
    value=(value<<8)|data[i]; bits+=8;
    while (bits>=6) { bits-=6; result+=alphabet[(value>>bits)&63]; }
  }
  if (bits) result+=alphabet[(value<<(6-bits))&63];
  return result;
}
std::array<unsigned char,32> Digest(const std::string& text) {
  std::array<unsigned char,32> bytes{};
#ifdef _WIN32
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  if (BCryptOpenAlgorithmProvider(&algorithm,BCRYPT_SHA256_ALGORITHM,nullptr,0)<0) throw AccountFailure(0);
  const auto status = BCryptHash(algorithm,nullptr,0,reinterpret_cast<PUCHAR>(const_cast<char*>(text.data())),
      static_cast<ULONG>(text.size()),bytes.data(),static_cast<ULONG>(bytes.size()));
  BCryptCloseAlgorithmProvider(algorithm,0);
  if (status<0) throw AccountFailure(0);
#else
  unsigned size=0;
  if (EVP_Digest(text.data(),text.size(),bytes.data(),&size,EVP_sha256(),nullptr)!=1 || size!=32) throw AccountFailure(0);
#endif
  return bytes;
}
std::string Escape(const std::string& value) {
  std::string result;
  for (unsigned char c:value) {
    if (std::isalnum(c)||c=='-'||c=='_'||c=='.'||c=='~') result+=c;
    else { char escaped[4]; std::snprintf(escaped,sizeof(escaped),"%%%02X",c); result+=escaped; }
  }
  return result;
}
std::string Lower(std::string value) {
  std::transform(value.begin(),value.end(),value.begin(),[](unsigned char c){return static_cast<char>(std::tolower(c));});
  return value;
}
std::string String(const nlohmann::json& value, const char* key, std::string fallback={}) {
  return value.is_object() && value.contains(key) && value[key].is_string() ? value[key].get<std::string>() : fallback;
}
}
std::string RandomAccountValue() {
  std::array<unsigned char,32> bytes{};
#ifdef _WIN32
  if (BCryptGenRandom(nullptr,bytes.data(),static_cast<ULONG>(bytes.size()),BCRYPT_USE_SYSTEM_PREFERRED_RNG)<0)
    throw AccountFailure(0);
#else
  if (RAND_bytes(bytes.data(),static_cast<int>(bytes.size()))!=1) throw AccountFailure(0);
#endif
  return Base64URL(bytes.data(),bytes.size());
}
std::string AccountChallenge(const std::string& verifier) {
  const auto bytes=Digest(verifier); return Base64URL(bytes.data(),bytes.size());
}
std::string AccountAuthorizationUrl(const std::string& client,const std::string& redirect,
                                  const std::string& state,const std::string& verifier) {
  return std::string(kAccountOrigin)+"/oauth/authorize?response_type=code&client_id="+Escape(client)+
      "&redirect_uri="+Escape(redirect)+"&state="+Escape(state)+"&scope="+Escape(kAccountScopes)+
      "&code_challenge="+AccountChallenge(verifier)+"&code_challenge_method=S256";
}
bool SameAccountState(const std::string& a,const std::string& b) {
  unsigned difference=static_cast<unsigned>(a.size()^b.size());
  for (std::size_t i=0;i<a.size();++i) difference|=static_cast<unsigned char>(a[i]) ^
      static_cast<unsigned char>(i<b.size()?b[i]:0);
  return difference==0 && !a.empty();
}
std::string AccountBookmarkID(const nlohmann::json& item) {
  auto id=String(item,"id");
  const bool uuid=id.size()==36 && id[8]=='-' && id[13]=='-' && id[18]=='-' && id[23]=='-' &&
      std::all_of(id.begin(),id.end(),[](unsigned char c){return c=='-'||std::isxdigit(c);});
  if (uuid) return Lower(id);
  const auto bytes=Digest(String(item,"url"));
  id.clear();
  for (unsigned i=0;i<16;++i) {
    if (i==4||i==6||i==8||i==10) id+='-';
    char hex[3]; std::snprintf(hex,sizeof(hex),"%02x",bytes[i]); id+=hex;
  }
  return id;
}
nlohmann::json VisibleAccountBookmarks(const nlohmann::json& raw) {
  auto result=nlohmann::json::array();
  if (!raw.is_array()) throw AccountFailure(0);
  for (const auto& item:raw) {
    const auto url=String(item,"url");
    if (url.empty()) continue;
    result.push_back({{"id",AccountBookmarkID(item)},{"url",url},
        {"title",String(item,"title",String(item,"name",url))},
        {"created_at",String(item,"created_at",String(item,"createdAt"))}});
  }
  return result;
}
nlohmann::json MutateAccountBookmarks(nlohmann::json raw,const std::string& action,const nlohmann::json& params) {
  if (!raw.is_array()) throw AccountFailure(0);
  if (action=="clear") return nlohmann::json::array();
  if (action=="remove") {
    const auto id=Lower(params.at("id").get<std::string>());
    raw.erase(std::remove_if(raw.begin(),raw.end(),[&](const auto& item){
      return item.is_object() && AccountBookmarkID(item)==id;
    }),raw.end());
  } else if (action=="add") {
    const auto url=params.at("url").get<std::string>();
    if (!url.starts_with("https://") && !url.starts_with("http://")) throw std::invalid_argument("A web URL is required");
    for (const auto& item:raw) if (String(item,"url")==url) return raw;
    BookmarkStore temporary;
    temporary.Add(String(params,"title",url),url);
    raw.push_back(nlohmann::json::parse(temporary.ToJson()).at(0));
  }
  return raw;
}
}  // namespace kelpie::account
