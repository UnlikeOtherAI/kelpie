#include "account_service.h"
#include "kelpie/response_helpers.h"

namespace kelpie::account {
using json=nlohmann::json;
AccountService::AccountService(BookmarkStore& local,AccountRequest request) : local_(local),request_(std::move(request)) {
}
AccountRequest AccountService::RequestLocked() const {
  if (request_) return request_;
  auto transport=transport_;
  return [transport](const auto& p,const auto& m,const auto& t,const auto& b,const auto& v) {
    return transport->Request(p,m,t,b,v);
  };
}
AccountService::~AccountService() { Shutdown(); if (task_.valid()) task_.wait(); }
AccountState AccountService::State() const { std::lock_guard lock(mutex_); return state_; }
std::string AccountService::Bookmarks() const {
  std::lock_guard lock(mutex_);
  return state_.signed_in ? VisibleAccountBookmarks(bookmarks_).dump() : local_.ToJson();
}
void AccountService::CheckGeneration(std::uint64_t generation) const {
  std::lock_guard lock(mutex_);
  if (generation!=generation_) throw AccountFailure(401);
}
void AccountService::SignOut() {
  std::shared_ptr<AccountLogin> login;
  std::shared_ptr<AccountTransport> transport;
  { std::lock_guard lock(mutex_); ++generation_; token_.clear(); state_={};
    bookmarks_=json::array(); login=std::move(login_); transport=transport_; }
  if (login) login->Cancel();
  transport->Cancel();
}
void AccountService::Shutdown() { SignOut(); }
bool AccountService::Drain() {
  if (!task_.valid()) return true;
  if (task_.wait_for(std::chrono::seconds(0))!=std::future_status::ready) return false;
  task_.get(); return true;
}
void AccountService::Poll() {
  if (task_.valid() && task_.wait_for(std::chrono::seconds(0))==std::future_status::ready) task_.get();
  bool expired;
  { std::lock_guard lock(mutex_); expired=state_.signed_in && std::chrono::steady_clock::now()>=expiry_; }
  if (expired) { SignOut(); std::lock_guard lock(mutex_); state_.error="Your UOA session expired. Sign in again."; }
}
void AccountService::Fail(std::uint64_t generation,const std::string& message,int status) {
  std::lock_guard lock(mutex_);
  if (generation!=generation_) return;
  if (status==401) { ++generation_; token_.clear(); bookmarks_=json::array(); state_={}; }
  state_.error=message; state_.busy=false; state_.signing_in=false;
}
bool AccountService::StartTask(std::function<void(std::uint64_t)> task,bool login) {
  Poll();
  if (task_.valid()) return false;
  std::uint64_t generation;
  { std::lock_guard lock(mutex_); generation=generation_; state_.busy=true; state_.signing_in=login; state_.error.clear(); }
  task_=std::async(std::launch::async,[this,task=std::move(task),generation] {
    try { task(generation); }
    catch (const AccountFailure& failure) { Fail(generation,failure.what(),failure.status); }
    catch (...) { Fail(generation,"UOA could not complete this request. Please try again."); }
    std::lock_guard lock(mutex_);
    if (generation==generation_) { state_.busy=false; state_.signing_in=false; login_.reset(); }
  });
  return true;
}
bool AccountService::StartSignIn(const std::filesystem::path& profile,const std::function<bool(const std::string&)>& open) {
  Poll();
  if (State().signed_in || task_.valid()) return false;
  { std::lock_guard lock(mutex_); transport_=std::make_shared<AccountTransport>(); }
  return StartTask([this,profile,open](std::uint64_t generation) {
    auto login=std::make_shared<AccountLogin>();
    { std::lock_guard lock(mutex_); if (generation!=generation_) return; login_=login; }
    AccountRequest request;
    { std::lock_guard lock(mutex_); request=RequestLocked(); }
    const auto token=login->Run(request,profile,open);
    CheckGeneration(generation);
    CompleteSignIn(token,generation);
  },true);
}
void AccountService::CompleteSignIn(const AccountToken& token,std::uint64_t generation) {
  AccountRequest request;
  { std::lock_guard lock(mutex_); if (generation!=generation_) return; request=RequestLocked(); }
  const auto identity=json::parse(request("/oauth/me","GET",token.token,{},{}).body);
  CheckGeneration(generation);
  const auto name=identity.value("name",json()).is_string()?identity["name"].get<std::string>():std::string();
  const auto email=identity.at("email").get<std::string>();
  if (identity.at("sub").get<std::string>().empty() || email.empty()) throw AccountFailure(0);
  const auto favorites=json::parse(request(kAccountBookmarks,"GET",token.token,{},{}).body);
  auto list=favorites.value("value",json());
  if (list.is_null()) list=json::array();
  VisibleAccountBookmarks(list); // Validate before switching away from local favorites.
  CheckGeneration(generation);
  std::string avatar;
  try { avatar=request("/oauth/me/avatar","GET",token.token,{},{}).body; } catch (...) {}
  std::lock_guard lock(mutex_);
  if (generation!=generation_) return;
  token_=token.token; bookmarks_=std::move(list);
  expiry_=std::chrono::steady_clock::now()+std::chrono::milliseconds(static_cast<long long>(token.seconds*1000));
  state_={true,false,false,name,email,std::move(avatar),{}};
}
bool AccountService::StartBookmarkAction(std::string action,json params) {
  return StartTask([this,action=std::move(action),params=std::move(params)](std::uint64_t generation) {
    const auto result=BookmarkAction(action,params,generation);
    if (!result.value("success",false)) throw AccountFailure(0);
  },false);
}
json AccountService::BookmarkAction(const std::string& action,const json& params,std::optional<std::uint64_t> expected) {
  std::uint64_t generation;
  std::string token;
  AccountRequest request;
  {
    std::lock_guard lock(mutex_);
    generation=generation_;
    if (expected && *expected!=generation) throw AccountFailure(401);
    if (!state_.signed_in) {
      if (action=="add") local_.Add(params.value("title",params.at("url").get<std::string>()),params.at("url").get<std::string>());
      else if (action=="remove") local_.Remove(params.at("id").get<std::string>());
      else if (action=="clear") local_.RemoveAll();
      return action=="clear" ? SuccessResponse({{"cleared",true}}) :
          SuccessResponse({{"bookmarks",json::parse(local_.ToJson())}});
    }
    token=token_; request=RequestLocked();
    if (action=="list") return SuccessResponse({{"bookmarks",VisibleAccountBookmarks(bookmarks_)}});
  }
  try {
    const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(15);
    std::unique_lock lock(operation_,std::defer_lock);
    if (!lock.try_lock_until(deadline)) throw AccountFailure(0);
    for (int attempt=0;attempt<3;++attempt) {
      CheckGeneration(generation);
      if (std::chrono::steady_clock::now()>deadline) throw AccountFailure(0);
      const auto response=request(kAccountBookmarks,"GET",token,{},{});
      CheckGeneration(generation);
      auto existing=json::parse(response.body).value("value",json());
      if (existing.is_null()) existing=json::array();
      VisibleAccountBookmarks(existing);
      if (action!="refresh") {
        if (response.version.empty()) throw AccountFailure(428);
        const auto updated=MutateAccountBookmarks(existing,action,params);
        try {
          const auto saved=request(kAccountBookmarks,"PUT",token,json{{"value",updated}}.dump(),response.version);
          existing=json::parse(saved.body).at("value");
          VisibleAccountBookmarks(existing);
        } catch (const AccountFailure& failure) {
          if ((failure.status==409||failure.status==412) && attempt<2) continue;
          throw;
        }
      }
      std::lock_guard stateLock(mutex_);
      if (generation!=generation_) throw AccountFailure(401);
      bookmarks_=std::move(existing); state_.error.clear();
      return action=="clear" ? SuccessResponse({{"cleared",true}}) :
          SuccessResponse({{"bookmarks",VisibleAccountBookmarks(bookmarks_)}});
    }
    throw AccountFailure(409);
  } catch (const AccountFailure& failure) {
    Fail(generation,failure.what(),failure.status);
    return ErrorResponse("WEBVIEW_ERROR",failure.what());
  }
}
}  // namespace kelpie::account
