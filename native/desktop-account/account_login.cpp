#include "account_login.h"
#include <httplib.h>
#include <condition_variable>
#include <fstream>
#include <thread>
#include <cmath>
#include <algorithm>

namespace kelpie::account {
struct AccountLogin::Impl {
  httplib::Server server;
  std::thread listener;
  std::mutex mutex;
  std::condition_variable changed;
  std::atomic<bool> cancelled{false};
  std::atomic<bool> listener_done{false};
  bool completed=false;
  std::string code;
};
AccountLogin::AccountLogin() : impl_(std::make_unique<Impl>()) {}
AccountLogin::~AccountLogin() { Cancel(); if (impl_->listener.joinable()) impl_->listener.join(); }
void AccountLogin::Cancel() { impl_->cancelled=true; impl_->server.stop(); impl_->changed.notify_all(); }
AccountToken AccountLogin::Run(const AccountRequest& request,const std::filesystem::path& profile,
    const std::function<bool(const std::string&)>& open) {
  using json=nlohmann::json;
  auto& p=*impl_;
  const auto cache=profile/"uoa-public-client.json";
  json registration;
  { std::ifstream file(cache); if (file) registration=json::parse(file,nullptr,false); }
  int preferred=0;
  std::string client;
  if (registration.is_object() && registration.contains("port") && registration["port"].is_number_integer() &&
      registration.contains("client_id") && registration["client_id"].is_string()) {
    preferred=registration["port"].get<int>(); client=registration["client_id"].get<std::string>();
    if (preferred<1024||preferred>65535||client.size()>256) { preferred=0; client.clear(); }
  }
  p.server.set_read_timeout(2,0); p.server.set_write_timeout(2,0);
  p.server.set_payload_max_length(8192);
  p.server.set_keep_alive_max_count(1);
#ifdef _WIN32
  p.server.set_socket_options([](socket_t socket) {
    const BOOL exclusive=TRUE;
    if (setsockopt(socket,SOL_SOCKET,SO_EXCLUSIVEADDRUSE,reinterpret_cast<const char*>(&exclusive),sizeof(exclusive)))
      throw AccountFailure(0);
  });
#endif
  int port=preferred;
  if (!preferred || !p.server.bind_to_port("127.0.0.1",preferred)) {
    port=p.server.bind_to_any_port("127.0.0.1"); client.clear();
  }
  if (port<=0 || p.cancelled) throw AccountFailure(0);
  const std::string redirect="http://127.0.0.1:"+std::to_string(port)+"/oauth/callback";
  const auto state=RandomAccountValue(), verifier=RandomAccountValue();
  p.server.Get("/oauth/callback",[&p,state,port](const httplib::Request& req,httplib::Response& res) {
    res.set_header("Cache-Control","no-store"); res.set_header("Connection","close");
    res.set_header("Content-Security-Policy","default-src 'none'; frame-ancestors 'none'");
    // cpp-httplib collapses identical query pairs; verify the raw count too.
    const auto query=req.target.find('?');
    const bool unique=query!=std::string::npos && req.target.size()<=8192 &&
        static_cast<std::size_t>(1+std::count(req.target.begin()+query+1,req.target.end(),'&'))==req.params.size();
    const bool valid=unique && req.get_header_value("Host")=="127.0.0.1:"+std::to_string(port) &&
        req.get_param_value_count("state")==1 && SameAccountState(state,req.get_param_value("state")) &&
        ((req.get_param_value_count("code")==1 && !req.has_param("error") &&
          !req.get_param_value("code").empty() && req.get_param_value("code").size()<=4096) ||
         (req.get_param_value_count("error")==1 && !req.has_param("code")));
    std::lock_guard lock(p.mutex);
    if (!valid || p.completed || p.cancelled) { res.status=400; res.set_content("Invalid sign-in callback.","text/plain"); return; }
    p.completed=true;
    if (!req.has_param("error")) p.code=req.get_param_value("code");
    res.set_content("<!doctype html><title>Kelpie</title><h1>Return to Kelpie</h1><p>You can close this window.</p>","text/html");
    p.changed.notify_all();
  });
  p.listener=std::thread([&p] { p.server.listen_after_bind(); p.listener_done=true; });
  // stop() before listen_after_bind() becomes ready does nothing. Always finish
  // startup before honoring cancellation so destruction cannot join forever.
  while (!p.server.is_running() && !p.listener_done) std::this_thread::sleep_for(std::chrono::milliseconds(1));
  if (p.cancelled || p.listener_done) { p.server.stop(); throw AccountFailure(0); }
  if (client.empty()) {
    const auto result=request("/oauth/register","POST",{},json{{"client_name","Kelpie Desktop"},
        {"redirect_uris",{redirect}},{"token_endpoint_auth_method","none"},{"scope",kAccountScopes}}.dump(),{});
    client=json::parse(result.body).at("client_id").get<std::string>();
    if (client.empty()||client.size()>256) throw AccountFailure(0);
    std::ofstream file(cache,std::ios::trunc); file<<json{{"client_id",client},{"port",port}}.dump();
  }
  if (p.cancelled || !open(AccountAuthorizationUrl(client,redirect,state,verifier))) throw AccountFailure(0);
  {
    std::unique_lock lock(p.mutex);
    p.changed.wait_for(lock,std::chrono::minutes(5),[&p]{return p.completed||p.cancelled;});
    if (!p.completed || p.cancelled || p.code.empty()) throw AccountFailure(0);
  }
  p.server.stop();
  AccountResponse response;
  try {
    response=request("/oauth/token","POST",{},json{{"grant_type","authorization_code"},{"code",p.code},
        {"client_id",client},{"redirect_uri",redirect},{"code_verifier",verifier}}.dump(),{});
  } catch (const AccountFailure& failure) {
    if (failure.status==400 || failure.status==401) { std::error_code error; std::filesystem::remove(cache,error); }
    throw;
  }
  const auto token=json::parse(response.body);
  const auto value=token.at("access_token").get<std::string>();
  const auto seconds=token.at("expires_in").get<double>();
  auto type=token.value("token_type","");
  for (auto& c:type) c=static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  const std::string scopes=" "+token.value("scope",std::string(kAccountScopes))+" ";
  if (p.cancelled || value.empty() || type!="bearer" || !std::isfinite(seconds) || seconds<=0 || seconds>2592000 ||
      scopes.find(" settings.read ")==std::string::npos || scopes.find(" settings.write ")==std::string::npos)
    throw AccountFailure(403);
  return {value,seconds};
}
}  // namespace kelpie::account
