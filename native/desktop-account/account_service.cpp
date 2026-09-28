#include "account_service.h"
#include "kelpie/response_helpers.h"

namespace kelpie::account {
using json=nlohmann::json;
AccountService::AccountService(BookmarkStore& local,AccountRequest request,std::shared_ptr<AccountSessionStore> store)
    : local_(local),request_(std::move(request)),
      store_(store?std::move(store):std::make_shared<MemoryAccountSessionStore>()) {}
AccountRequest AccountService::RequestLocked() const {
  if (request_) return request_;
  auto transport=transport_;
  return [transport](const auto& p,const auto& m,const auto& t,const auto& b,const auto& v) {
    return transport->Request(p,m,t,b,v);
  };
}
AccountRequest AccountService::Request() const { std::lock_guard lock(mutex_); return RequestLocked(); }
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
void AccountService::Poll() {
  std::string url;
  std::function<bool(const std::string&)> open;
  std::uint64_t generation;
  {
    std::lock_guard lock(mutex_); generation=generation_;
    if (state_.signing_in) { url=std::move(pending_browser_url_); pending_browser_url_.clear(); open=open_browser_; }
  }
  // OS launch APIs and the private fallback window belong to the UI owner thread.
  if (!url.empty()) {
    bool opened=false;
    try { opened=open && open(url); } catch (...) {}
    if (!opened) {
      std::shared_ptr<AccountLogin> login;
      { std::lock_guard lock(mutex_); if (generation==generation_) login=login_; }
      if (login) login->Cancel();
      Fail(generation,"Could not open login/register. Please try again.");
    }
  }
  if (task_.valid() && task_.wait_for(std::chrono::seconds(0))==std::future_status::ready) task_.get();
  // A refresh token outlives the access token; without one (older UOA) expiry ends the session.
  bool expired;
  { std::lock_guard lock(mutex_); expired=state_.signed_in && refresh_token_.empty() && std::chrono::steady_clock::now()>=expiry_; }
  if (expired) { Reset(); std::lock_guard lock(mutex_); state_.error=AccountFailure(401).what(); }
}
void AccountService::Fail(std::uint64_t generation,const std::string& message,int status) {
  if (status==401) { ExpireSession(generation,message); return; }
  std::lock_guard lock(mutex_);
  if (generation!=generation_) return;
  pending_browser_url_.clear(); open_browser_={};
  // A sign-in that did not finish keeps no credentials in memory; storage is untouched.
  if (!state_.signed_in) { token_.clear(); refresh_token_.clear(); client_id_.clear(); }
  state_.error=message; state_.busy=false; state_.signing_in=false;
}
// A rejected session: signs out and deletes the stored session unless a newer attempt owns it.
void AccountService::ExpireSession(std::uint64_t generation,const std::string& message) {
  std::lock_guard storeLock(store_mutex_);
  {
    std::lock_guard lock(mutex_);
    if (generation!=generation_) return;
    ++generation_; token_.clear(); refresh_token_.clear(); client_id_.clear();
    bookmarks_=json::array(); state_={}; state_.error=message;
    pending_browser_url_.clear(); open_browser_={};
  }
  ClearStoredLocked();
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
void AccountService::CompleteSignIn(const AccountToken& token,std::uint64_t generation) {
  // Persists the (rotated) refresh token before the access token is used.
  if (!AdoptToken(token,generation)) return;
  const auto identity=json::parse(Authorized(generation,"/oauth/me","GET").body);
  CheckGeneration(generation);
  const auto name=identity.value("name",json()).is_string()?identity["name"].get<std::string>():std::string();
  const auto email=identity.at("email").get<std::string>();
  if (identity.at("sub").get<std::string>().empty() || email.empty()) throw AccountFailure(0);
  const auto favorites=json::parse(Authorized(generation,kAccountBookmarks,"GET").body);
  auto list=favorites.value("value",json());
  if (list.is_null()) list=json::array();
  VisibleAccountBookmarks(list); // Validate before switching away from local favorites.
  CheckGeneration(generation);
  std::string avatar, current;
  AccountRequest request;
  { std::lock_guard lock(mutex_); current=token_; request=RequestLocked(); }
  try { avatar=request("/oauth/me/avatar","GET",current,{},{}).body; } catch (...) {}
  std::lock_guard lock(mutex_);
  if (generation!=generation_) return;
  bookmarks_=std::move(list);
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
    if (action=="list") return SuccessResponse({{"bookmarks",VisibleAccountBookmarks(bookmarks_)}});
  }
  try {
    const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(15);
    std::unique_lock lock(operation_,std::defer_lock);
    if (!lock.try_lock_until(deadline)) throw AccountFailure(0);
    for (int attempt=0;attempt<3;++attempt) {
      CheckGeneration(generation);
      if (std::chrono::steady_clock::now()>deadline) throw AccountFailure(0);
      const auto response=Authorized(generation,kAccountBookmarks,"GET");
      CheckGeneration(generation);
      auto existing=json::parse(response.body).value("value",json());
      if (existing.is_null()) existing=json::array();
      VisibleAccountBookmarks(existing);
      if (action!="refresh") {
        if (response.version.empty()) throw AccountFailure(428);
        const auto updated=MutateAccountBookmarks(existing,action,params);
        try {
          const auto saved=Authorized(generation,kAccountBookmarks,"PUT",json{{"value",updated}}.dump(),response.version);
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
