#include "account_transport.h"
#include <curl/curl.h>
#include <memory>
#include <strings.h>

namespace kelpie::account {
void AccountTransport::Cancel() { std::lock_guard lock(mutex_); ++generation_; cancelled_=true; }
AccountResponse AccountTransport::Request(const std::string& path,const std::string& method,
    const std::string& token,const std::string& body,const std::string& version) {
  if (!path.starts_with("/oauth/") || path.find("..")!=std::string::npos ||
      token.find_first_of("\r\n")!=std::string::npos || version.find_first_of("\r\n")!=std::string::npos)
    throw AccountFailure(400);
  static const int initialized=curl_global_init(CURL_GLOBAL_DEFAULT);
  if (initialized!=CURLE_OK) throw AccountFailure(0);
  using Handle=std::unique_ptr<CURL,decltype(&curl_easy_cleanup)>;
  Handle curl(curl_easy_init(),curl_easy_cleanup);
  if (!curl) throw AccountFailure(0);
  unsigned generation;
  { std::lock_guard lock(mutex_); if (cancelled_) throw AccountFailure(0); generation=generation_; }
  struct Context { AccountTransport* owner; unsigned generation; AccountResponse response; } context{this,generation,{}};
  curl_slist* headers=nullptr;
  headers=curl_slist_append(headers,"Content-Type: application/json");
  headers=curl_slist_append(headers,"Cache-Control: no-store");
  if (!token.empty()) headers=curl_slist_append(headers,("Authorization: Bearer "+token).c_str());
  if (!version.empty()) headers=curl_slist_append(headers,("If-Match: "+version).c_str());
  std::unique_ptr<curl_slist,decltype(&curl_slist_free_all)> cleanup(headers,curl_slist_free_all);
  const std::string url="https://authentication.unlikeotherai.com"+path;
  curl_easy_setopt(curl.get(),CURLOPT_URL,url.c_str());
  curl_easy_setopt(curl.get(),CURLOPT_CUSTOMREQUEST,method.c_str());
  curl_easy_setopt(curl.get(),CURLOPT_HTTPHEADER,headers);
  curl_easy_setopt(curl.get(),CURLOPT_FOLLOWLOCATION,0L);
  curl_easy_setopt(curl.get(),CURLOPT_TIMEOUT_MS,8000L);
  curl_easy_setopt(curl.get(),CURLOPT_CONNECTTIMEOUT_MS,2500L);
  curl_easy_setopt(curl.get(),CURLOPT_NOSIGNAL,1L);
  if (!body.empty()) { curl_easy_setopt(curl.get(),CURLOPT_POSTFIELDS,body.data()); curl_easy_setopt(curl.get(),CURLOPT_POSTFIELDSIZE,static_cast<long>(body.size())); }
  curl_easy_setopt(curl.get(),CURLOPT_WRITEDATA,&context);
  curl_easy_setopt(curl.get(),CURLOPT_WRITEFUNCTION,+[](char* data,size_t size,size_t count,void* raw)->size_t {
    auto& c=*static_cast<Context*>(raw); const auto bytes=size*count;
    if (bytes>2*1024*1024-c.response.body.size()) return 0;
    c.response.body.append(data,bytes); return bytes;
  });
  curl_easy_setopt(curl.get(),CURLOPT_HEADERDATA,&context);
  curl_easy_setopt(curl.get(),CURLOPT_HEADERFUNCTION,+[](char* data,size_t size,size_t count,void* raw)->size_t {
    auto& c=*static_cast<Context*>(raw); std::string line(data,size*count);
    if (line.size()>5 && strncasecmp(line.c_str(),"etag:",5)==0) {
      const auto first=line.find_first_not_of(" \t",5),last=line.find_last_not_of(" \r\n\t");
      if (first!=std::string::npos && last>=first) c.response.version=line.substr(first,last-first+1);
    }
    return size*count;
  });
  curl_easy_setopt(curl.get(),CURLOPT_NOPROGRESS,0L);
  curl_easy_setopt(curl.get(),CURLOPT_XFERINFODATA,&context);
  curl_easy_setopt(curl.get(),CURLOPT_XFERINFOFUNCTION,+[](void* raw,curl_off_t,curl_off_t,curl_off_t,curl_off_t)->int {
    const auto& c=*static_cast<Context*>(raw); std::lock_guard lock(c.owner->mutex_);
    return c.owner->generation_!=c.generation;
  });
  if (curl_easy_perform(curl.get())!=CURLE_OK) throw AccountFailure(0);
  long status=0; curl_easy_getinfo(curl.get(),CURLINFO_RESPONSE_CODE,&status);
  if (status<200||status>=300) throw AccountFailure(static_cast<int>(status));
  return std::move(context.response);
}
}  // namespace kelpie::account
