// UOA session lifecycle: launch restore, token adoption and refresh, sign-out,
// shutdown and revocation. Storage writes happen only under store_mutex_ after
// a generation check, so a result from an older attempt can never write.
#include "account_service.h"
#include <utility>

namespace kelpie::account {
namespace {
using json = nlohmann::json;
// Refresh this long before expiry so a request never races the token's end.
constexpr auto kRefreshMargin = std::chrono::seconds(60);
}  // namespace

AccountSession AccountService::Reset() {
  std::shared_ptr<AccountLogin> login;
  std::shared_ptr<AccountTransport> transport;
  AccountSession session;
  {
    std::lock_guard lock(mutex_);
    ++generation_; token_.clear(); state_={}; bookmarks_=json::array(); expiry_={};
    session={std::exchange(client_id_,{}),std::exchange(refresh_token_,{})};
    login=std::move(login_); transport=transport_;
    pending_browser_url_.clear(); open_browser_={};
  }
  if (login) login->Cancel();
  transport->Cancel();
  return session;
}

void AccountService::SignOut() {
  auto session=Reset();
  {
    std::lock_guard lock(store_mutex_);
    // Storage holds the latest rotation, even one persisted while signing out.
    if (auto stored=LoadStoredLocked()) session=std::move(*stored);
    ClearStoredLocked();
  }
  Revoke(session);
}

void AccountService::Shutdown() {
  Reset();
  std::lock_guard lock(mutex_);
  for (auto& revoke:revokes_) if (revoke.transport) revoke.transport->Cancel();
}

bool AccountService::Drain() {
  if (task_.valid()) {
    if (task_.wait_for(std::chrono::seconds(0))!=std::future_status::ready) return false;
    task_.get();
  }
  std::lock_guard lock(mutex_);
  PruneRevokesLocked();
  return revokes_.empty();
}

bool AccountService::RestoreSession() {
  Poll();
  if (State().signed_in || task_.valid()) return false;
  std::optional<AccountSession> stored;
  { std::lock_guard lock(store_mutex_); stored=LoadStoredLocked(); }
  if (!stored) return false;
  { std::lock_guard lock(mutex_); transport_=std::make_shared<AccountTransport>(); }
  return StartTask([this,session=std::move(*stored)](std::uint64_t generation) {
    // Rejection throws 401, which signs out and clears storage; transient errors keep it.
    CompleteSignIn(RefreshAccountToken(Request(),session),generation);
  },true);
}

bool AccountService::StartSignIn(const std::filesystem::path& profile,const std::function<bool(const std::string&)>& open) {
  Poll();
  if (State().signed_in || task_.valid()) return false;
  std::optional<AccountSession> stored;
  { std::lock_guard lock(store_mutex_); stored=LoadStoredLocked(); }
  { std::lock_guard lock(mutex_); transport_=std::make_shared<AccountTransport>(); open_browser_=open; }
  return StartTask([this,profile,stored=std::move(stored)](std::uint64_t generation) {
    if (stored && ResumeStoredSession(*stored,generation)) return;
    InteractiveSignIn(profile,generation);
  },true);
}

// True once the stored session is handled; false when UOA rejected it and it was discarded.
bool AccountService::ResumeStoredSession(const AccountSession& session,std::uint64_t generation) {
  AccountToken token;
  try {
    token=RefreshAccountToken(Request(),session);
  } catch (const AccountFailure& failure) {
    if (failure.status!=401) throw;  // Transient: keep the stored session and stop.
    DiscardStoredSession(generation);
    return false;
  }
  CompleteSignIn(token,generation);
  return true;
}

void AccountService::InteractiveSignIn(const std::filesystem::path& profile,std::uint64_t generation) {
  auto login=std::make_shared<AccountLogin>();
  AccountRequest request;
  {
    std::lock_guard lock(mutex_);
    if (generation!=generation_) return;
    login_=login; request=RequestLocked();
  }
  const auto token=login->Run(request,profile,[this,generation](const std::string& url) {
    std::lock_guard lock(mutex_);
    if (generation!=generation_ || !state_.signing_in) return false;
    pending_browser_url_=url;
    return true;
  });
  CheckGeneration(generation);
  CompleteSignIn(token,generation);
}

// Persists the refresh token before the access token becomes usable. A token
// without one (older UOA) or a failed save leaves nothing stored to replay.
bool AccountService::AdoptToken(const AccountToken& token,std::uint64_t generation) {
  std::lock_guard storeLock(store_mutex_);
  { std::lock_guard lock(mutex_); if (generation!=generation_) return false; }
  const bool durable=!token.refresh_token.empty() && !token.client_id.empty();
  bool saved=false;
  if (durable) {
    try { saved=store_->Save({token.client_id,token.refresh_token}); } catch (...) {}
  }
  if (!saved) ClearStoredLocked();
  std::lock_guard lock(mutex_);
  if (generation!=generation_) return false;
  token_=token.token;
  refresh_token_=durable?token.refresh_token:std::string();
  client_id_=durable?token.client_id:std::string();
  expiry_=std::chrono::steady_clock::now()+std::chrono::milliseconds(static_cast<long long>(token.seconds*1000));
  return true;
}

// Returns a usable access token, refreshing once for all concurrent callers when
// it is within kRefreshMargin of expiry or when `rejected` is still current.
std::string AccountService::AccessToken(std::uint64_t generation,const std::string& rejected) {
  std::lock_guard single(refresh_);
  AccountSession session;
  AccountRequest request;
  {
    std::lock_guard lock(mutex_);
    if (generation!=generation_) throw AccountFailure(401);
    const bool fresh=std::chrono::steady_clock::now()+kRefreshMargin<expiry_;
    if (refresh_token_.empty() || (fresh && token_!=rejected)) return token_;
    session={client_id_,refresh_token_}; request=RequestLocked();
  }
  const auto token=RefreshAccountToken(request,session);
  if (!AdoptToken(token,generation)) throw AccountFailure(401);
  return token.token;
}

AccountResponse AccountService::Authorized(std::uint64_t generation,const std::string& path,
    const std::string& method,const std::string& body,const std::string& version) {
  const auto request=Request();
  const auto token=AccessToken(generation);
  try {
    return request(path,method,token,body,version);
  } catch (const AccountFailure& failure) {
    bool refreshable;
    { std::lock_guard lock(mutex_); refreshable=failure.status==401 && !refresh_token_.empty(); }
    if (!refreshable) throw;
  }
  // One forced refresh, then a single retry of the rejected request.
  return request(path,method,AccessToken(generation,token),body,version);
}

std::optional<AccountSession> AccountService::LoadStoredLocked() {
  try { return store_->Load(); } catch (...) { ClearStoredLocked(); return std::nullopt; }
}

void AccountService::ClearStoredLocked() {
  try { store_->Clear(); } catch (...) {}
}

void AccountService::DiscardStoredSession(std::uint64_t generation) {
  std::lock_guard storeLock(store_mutex_);
  { std::lock_guard lock(mutex_); if (generation!=generation_) return; }
  ClearStoredLocked();
}

// Fire-and-forget revocation on its own transport; Shutdown cancels it so exit never waits.
void AccountService::Revoke(const AccountSession& session) {
  if (session.refresh_token.empty() || session.client_id.empty()) return;
  std::lock_guard lock(mutex_);
  PruneRevokesLocked();
  auto transport=request_?nullptr:std::make_shared<AccountTransport>();
  AccountRequest request=request_;
  if (!request) request=[transport](const auto& p,const auto& m,const auto& t,const auto& b,const auto& v) {
    return transport->Request(p,m,t,b,v);
  };
  try {
    revokes_.push_back({transport,std::async(std::launch::async,[request,session] { RevokeAccountToken(request,session); })});
  } catch (...) {}  // Best effort: a revoke that cannot start is skipped.
}

void AccountService::PruneRevokesLocked() {
  std::erase_if(revokes_,[](const PendingRevoke& revoke) {
    return revoke.done.wait_for(std::chrono::seconds(0))==std::future_status::ready;
  });
}
}  // namespace kelpie::account
