#include "account_service.h"
#include <cassert>
#include <condition_variable>
#include <fstream>
#include <iterator>
#include <thread>
#ifndef _WIN32
#include <sys/stat.h>
#endif

using namespace kelpie::account;
using json=nlohmann::json;
namespace {
constexpr char kClient[]="client-1";
AccountSession Stored(const std::string& token="refresh-0") { return {kClient,token}; }

struct FakeStore final : AccountSessionStore {
  std::mutex mutex;
  std::optional<AccountSession> value;
  int saves=0;
  explicit FakeStore(std::optional<AccountSession> initial={}) : value(std::move(initial)) {}
  std::optional<AccountSession> Load() override { std::lock_guard lock(mutex); return value; }
  bool Save(const AccountSession& session) override { std::lock_guard lock(mutex); value=session; ++saves; return true; }
  void Clear() override { std::lock_guard lock(mutex); value.reset(); }
  std::optional<AccountSession> Get() { std::lock_guard lock(mutex); return value; }
};

// UOA with refresh-token rotation, revocation and one favourites document.
struct FakeUoa {
  std::mutex mutex;
  std::condition_variable changed;
  int token_status=200;  // 0 is a network failure.
  bool rotate=true, garbage=false, hold_token=false, token_waiting=false;
  int refreshes=0, resource_401s=0, registrations=0;
  double expires=3600;
  std::string issued="refresh-0", last_token, me_token;
  std::optional<AccountSession> stored_at_me;
  std::vector<json> revoked;
  std::shared_ptr<FakeStore> store;
  json list=json::array({{{"url","https://cloud.example/"},{"name","Cloud"}}});

  AccountResponse Request(const std::string& path,const std::string& method,const std::string& token,
      const std::string& body,const std::string&) {
    std::unique_lock lock(mutex);
    if (path=="/oauth/token") return Token(lock,json::parse(body));
    if (path=="/oauth/revoke") { revoked.push_back(json::parse(body)); return {"{}",{}}; }
    if (path=="/oauth/register") { ++registrations; throw AccountFailure(503); }
    last_token=token;
    if (resource_401s>0) { --resource_401s; throw AccountFailure(401); }
    if (path=="/oauth/me") {
      me_token=token; if (store) stored_at_me=store->Get();
      return {R"({"sub":"user","email":"user@example.org","name":"User"})",{}};
    }
    if (path=="/oauth/me/avatar") throw AccountFailure(404);
    assert(path==kAccountBookmarks);
    if (method=="PUT") list=json::parse(body).at("value");
    return {json{{"value",list}}.dump(),"\"v1\""};
  }
  AccountResponse Token(std::unique_lock<std::mutex>& lock,const json& request) {
    assert(request.at("grant_type")=="refresh_token");
    ++refreshes; token_waiting=true; changed.notify_all();
    changed.wait(lock,[&]{return !hold_token;});
    token_waiting=false;
    if (token_status==0) throw AccountFailure(0);
    if (token_status!=200) throw AccountFailure(token_status);
    if (garbage) return {"<html>maintenance</html>",{}};
    if (request.at("client_id")!=kClient || request.at("refresh_token")!=issued) throw AccountFailure(400);
    issued="refresh-"+std::to_string(refreshes);
    json response{{"access_token","access-"+std::to_string(refreshes)},{"token_type","Bearer"},
        {"expires_in",expires},{"scope",kAccountScopes}};
    if (rotate) response["refresh_token"]=issued;
    return {response.dump(),{}};
  }
  AccountRequest Transport() {
    return [this](const auto& p,const auto& m,const auto& t,const auto& b,const auto& v){return Request(p,m,t,b,v);};
  }
  template <typename F> void Set(F change) { std::lock_guard lock(mutex); change(); }
  void WaitForToken() { std::unique_lock lock(mutex); changed.wait(lock,[&]{return token_waiting;}); }
  void Release() { Set([&]{ hold_token=false; }); changed.notify_all(); }
};

// Waits for account work and revocations without Poll's expiry handling.
void Settle(AccountService& account) {
  const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(5);
  while (!account.Drain()) {
    assert(std::chrono::steady_clock::now()<deadline);
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
}
std::filesystem::path Profile() { return std::filesystem::temp_directory_path(); }

void RestorePersistsRotationBeforeUse() {
  kelpie::BookmarkStore local; local.Add("Local","https://local.example/");
  auto store=std::make_shared<FakeStore>(Stored());
  FakeUoa uoa; uoa.store=store; uoa.hold_token=true;
  AccountService account(local,uoa.Transport(),store);
  assert(account.RestoreSession());
  uoa.WaitForToken();
  assert(account.State().signing_in && !account.State().signed_in);
  uoa.Release(); Settle(account);
  const auto state=account.State();
  assert(state.signed_in && !state.signing_in && state.email=="user@example.org" && state.error.empty());
  assert(store->Get()==Stored("refresh-1") && uoa.stored_at_me==Stored("refresh-1") && uoa.me_token=="access-1");
  assert(json::parse(account.Bookmarks()).at(0).at("url")=="https://cloud.example/");
  assert(!account.RestoreSession());
}
void RestoreWithoutStoredSessionDoesNothing() {
  kelpie::BookmarkStore local;
  auto store=std::make_shared<FakeStore>();
  FakeUoa uoa;
  AccountService account(local,uoa.Transport(),store);
  assert(!account.RestoreSession());
  assert(!account.State().signing_in && uoa.refreshes==0);
}
void RejectedRestoreClearsStorage() {
  for (int status:{400,401,403}) {
    kelpie::BookmarkStore local;
    auto store=std::make_shared<FakeStore>(Stored());
    FakeUoa uoa; uoa.token_status=status;
    AccountService account(local,uoa.Transport(),store);
    assert(account.RestoreSession()); Settle(account);
    const auto state=account.State();
    assert(!state.signed_in && !state.signing_in && state.error==AccountFailure(401).what());
    assert(!store->Get() && uoa.registrations==0);
  }
}
void TransientRestoreKeepsStorage() {
  for (int status:{0,408,429,500,503,200}) {
    kelpie::BookmarkStore local;
    auto store=std::make_shared<FakeStore>(Stored());
    FakeUoa uoa; uoa.token_status=status; uoa.garbage=status==200;
    AccountService account(local,uoa.Transport(),store);
    assert(account.RestoreSession()); Settle(account);
    const auto state=account.State();
    assert(!state.signed_in && !state.signing_in && state.error==kAccountUnreachable);
    assert(store->Get()==Stored() && store->saves==0);
  }
}
void SignInTriesStoredSessionFirst() {
  int opened=0;
  auto open=[&](const std::string&) { ++opened; return true; };
  {
    kelpie::BookmarkStore local;
    auto store=std::make_shared<FakeStore>(Stored());
    FakeUoa uoa; AccountService account(local,uoa.Transport(),store);
    assert(account.StartSignIn(Profile(),open)); Settle(account);
    assert(account.State().signed_in && opened==0 && uoa.registrations==0 && store->Get()==Stored("refresh-1"));
  }
  {
    kelpie::BookmarkStore local;
    auto store=std::make_shared<FakeStore>(Stored());
    FakeUoa uoa; uoa.token_status=400;
    AccountService account(local,uoa.Transport(),store);
    assert(account.StartSignIn(Profile(),open)); Settle(account);
    assert(uoa.registrations==1 && !store->Get());  // Rejected: straight into interactive login.
  }
  {
    kelpie::BookmarkStore local;
    auto store=std::make_shared<FakeStore>(Stored());
    FakeUoa uoa; uoa.token_status=0;
    AccountService account(local,uoa.Transport(),store);
    assert(account.StartSignIn(Profile(),open)); Settle(account);
    assert(uoa.registrations==0 && store->Get()==Stored() && account.State().error==kAccountUnreachable);
  }
}
void RefreshBeforeRequestIsSingleFlight() {
  kelpie::BookmarkStore local;
  auto store=std::make_shared<FakeStore>();
  FakeUoa uoa; uoa.store=store; uoa.expires=30;
  AccountService account(local,uoa.Transport(),store);
  account.CompleteSignIn({"access-0",30,"refresh-0",kClient},0);  // Inside the 60 s margin.
  assert(account.State().signed_in && uoa.me_token!="access-0" && uoa.refreshes>0);
  assert(store->Get()==Stored(uoa.issued) && uoa.stored_at_me->refresh_token!="refresh-0");
  const int before=uoa.refreshes;
  uoa.Set([&]{ uoa.expires=3600; uoa.hold_token=true; });
  auto first=std::async(std::launch::async,[&]{return account.BookmarkAction("refresh",json::object());});
  auto second=std::async(std::launch::async,[&]{return account.BookmarkAction("refresh",json::object());});
  uoa.WaitForToken(); uoa.Release();
  assert(first.get().at("success")==true && second.get().at("success")==true);
  assert(uoa.refreshes==before+1 && store->Get()==Stored(uoa.issued));
}
void UnauthorizedRequestRefreshesOnceAndRetries() {
  kelpie::BookmarkStore local;
  auto store=std::make_shared<FakeStore>();
  FakeUoa uoa; AccountService account(local,uoa.Transport(),store);
  account.CompleteSignIn({"access-0",3600,"refresh-0",kClient},0);
  assert(uoa.refreshes==0 && store->Get()==Stored());
  uoa.Set([&]{ uoa.resource_401s=1; });
  assert(account.BookmarkAction("add",{{"url","https://new.example/"}}).at("success")==true);
  assert(uoa.refreshes==1 && uoa.last_token=="access-1" && store->Get()==Stored("refresh-1"));
  assert(uoa.list.size()==2 && account.State().signed_in);
  uoa.Set([&]{ uoa.resource_401s=2; });  // Still rejected after the forced refresh.
  assert(!account.BookmarkAction("refresh",json::object()).at("success").get<bool>());
  assert(uoa.refreshes==2 && !account.State().signed_in && !store->Get());
}
void RefreshFailuresDuringRequests() {
  kelpie::BookmarkStore local;
  auto store=std::make_shared<FakeStore>();
  FakeUoa uoa; AccountService account(local,uoa.Transport(),store);
  account.CompleteSignIn({"access-0",3600,"refresh-0",kClient},0);
  uoa.Set([&]{ uoa.resource_401s=1; uoa.token_status=503; });
  assert(!account.BookmarkAction("refresh",json::object()).at("success").get<bool>());
  assert(account.State().signed_in && account.State().error==kAccountUnreachable && store->Get()==Stored());
  uoa.Set([&]{ uoa.resource_401s=1; uoa.token_status=400; });
  assert(!account.BookmarkAction("refresh",json::object()).at("success").get<bool>());
  const auto state=account.State();
  assert(!state.signed_in && state.error==AccountFailure(401).what() && !store->Get());
  assert(account.Bookmarks()==local.ToJson());
}
void ExpiryKeepsRefreshableSession() {
  kelpie::BookmarkStore local;
  auto store=std::make_shared<FakeStore>();
  FakeUoa uoa; uoa.expires=0.001;
  AccountService account(local,uoa.Transport(),store);
  account.CompleteSignIn({"access-0",0.001,"refresh-0",kClient},0);
  std::this_thread::sleep_for(std::chrono::milliseconds(5));
  account.Poll();
  assert(account.State().signed_in && store->Get());
}
void SignOutClearsAndRevokes() {
  kelpie::BookmarkStore local;
  auto store=std::make_shared<FakeStore>();
  FakeUoa uoa; AccountService account(local,uoa.Transport(),store);
  account.CompleteSignIn({"access-0",3600,"refresh-0",kClient},0);
  account.SignOut();
  assert(!store->Get() && !account.State().signed_in);
  Settle(account);
  assert(uoa.revoked.size()==1 && uoa.revoked.at(0)==json({{"token","refresh-0"},{"client_id",kClient}}));
}
void ShutdownKeepsStorage() {
  kelpie::BookmarkStore local;
  auto store=std::make_shared<FakeStore>();
  FakeUoa uoa; AccountService account(local,uoa.Transport(),store);
  account.CompleteSignIn({"access-0",3600,"refresh-0",kClient},0);
  account.Shutdown(); Settle(account);
  assert(!account.State().signed_in && store->Get()==Stored() && uoa.revoked.empty());
}
void OlderServerStaysMemoryOnly() {
  {
    kelpie::BookmarkStore local;
    auto store=std::make_shared<FakeStore>(Stored("stale"));
    FakeUoa uoa; AccountService account(local,uoa.Transport(),store);
    account.CompleteSignIn({"access-0",3600,{},kClient},0);
    assert(account.State().signed_in && !store->Get());
    account.SignOut(); Settle(account);
    assert(uoa.revoked.empty());
  }
  kelpie::BookmarkStore local;
  auto store=std::make_shared<FakeStore>(Stored());
  FakeUoa uoa; uoa.rotate=false; uoa.expires=0.001;
  AccountService account(local,uoa.Transport(),store);
  assert(account.RestoreSession()); Settle(account);
  assert(account.State().signed_in && !store->Get());
  std::this_thread::sleep_for(std::chrono::milliseconds(5));
  account.Poll();  // Without a refresh token, expiry still signs out.
  assert(!account.State().signed_in && account.State().error==AccountFailure(401).what());
}
void StaleGenerationNeverWritesStorage() {
  kelpie::BookmarkStore local;
  auto store=std::make_shared<FakeStore>(Stored());
  FakeUoa uoa; uoa.hold_token=true;
  AccountService account(local,uoa.Transport(),store);
  assert(account.RestoreSession());
  uoa.WaitForToken();
  account.SignOut();
  assert(!store->Get());
  uoa.Release(); Settle(account);
  assert(!store->Get() && store->saves==0 && !account.State().signed_in);

  // A late rejection from the old attempt cannot clear a newer session.
  store->Save(Stored());
  uoa.Set([&]{ uoa.hold_token=true; uoa.issued="refresh-0"; uoa.token_status=400; });
  assert(account.RestoreSession());
  uoa.WaitForToken();
  account.SignOut();
  account.CompleteSignIn({"access-new",3600,"refresh-new",kClient},2);  // Two sign-outs so far.
  assert(account.State().signed_in && store->Get()==Stored("refresh-new"));
  uoa.Release(); Settle(account);
  assert(account.State().signed_in && store->Get()==Stored("refresh-new"));
}
void TokenParsing() {
  const auto token=ParseAccountToken(R"({"access_token":"a","token_type":"Bearer","expires_in":60,
      "refresh_token":"r","refresh_token_expires_in":86400})","c");
  assert(token.token=="a" && token.refresh_token=="r" && token.client_id=="c");
  assert(ParseAccountToken(R"({"access_token":"a","token_type":"bearer","expires_in":60,"refresh_token":"bad value"})","c")
      .refresh_token.empty());
  assert(EncodeAccountSession(Stored())==R"({"client_id":"client-1","refresh_token":"refresh-0"})");
  assert(DecodeAccountSession(EncodeAccountSession(Stored()))==Stored());
  for (const char* bad:{"not json","[]",R"({"client_id":"c"})",R"({"client_id":"c","refresh_token":""})",
                        R"({"client_id":1,"refresh_token":"r"})"})
    assert(!DecodeAccountSession(bad));
}
void AccountLabels() {
  AccountState state;
  assert(AccountLabel(state)=="Login/register");
  state.signing_in=true;  // Launch restore and interactive login share this state.
  assert(AccountLabel(state)=="Signing in\xE2\x80\xA6");
  state={}; state.error=kAccountUnreachable;
  assert(AccountLabel(state)==std::string("Login/register \xE2\x80\x94 ")+kAccountUnreachable);
  state={}; state.signed_in=true; state.busy=true; state.email="user@example.org";
  assert(AccountLabel(state)=="user@example.org \xE2\x80\x94 syncing");
}
std::string ReadFile(const std::filesystem::path& path) {
  std::ifstream input(path,std::ios::binary); return {std::istreambuf_iterator<char>(input),{}};
}
void PlatformStoreRoundTrip() {
  const auto root=std::filesystem::temp_directory_path()/("kelpie-session-"+RandomAccountValue());
  std::filesystem::create_directories(root);
  auto store=MakeAccountSessionStore(root);
  assert(!store->Load());
  const AccountSession first{kClient,"refresh-secret-first"}, second{kClient,"refresh-secret-second"};
  assert(store->Save(first) && store->Load()==first);
  assert(store->Save(second) && MakeAccountSessionStore(root)->Load()==second);
  std::filesystem::path sealed;
  for (const auto& entry:std::filesystem::recursive_directory_iterator(root)) {
    if (!entry.is_regular_file()) continue;
    const auto name=entry.path().filename().string();
    assert(name.find(".tmp")==std::string::npos);
    assert(ReadFile(entry.path()).find("refresh-secret")==std::string::npos);
    if (name==kAccountSessionKey) sealed=entry.path();
#ifndef _WIN32
    struct stat info{}; assert(stat(entry.path().c_str(),&info)==0 && (info.st_mode&0777)==0600);
#endif
  }
  assert(!sealed.empty());
#ifndef _WIN32
  struct stat directory{}; assert(stat(sealed.parent_path().c_str(),&directory)==0 && (directory.st_mode&0777)==0700);
#endif
  auto bytes=ReadFile(sealed);
  bytes.back()=static_cast<char>(bytes.back()^0x5a);
  { std::ofstream output(sealed,std::ios::binary|std::ios::trunc); output<<bytes; }
  assert(!store->Load() && !std::filesystem::exists(sealed));  // Corrupt data is deleted, never fatal.
  assert(store->Save(first));
  store->Clear();
  assert(!store->Load() && !std::filesystem::exists(sealed));
  std::filesystem::remove_all(root);
}
}  // namespace
int main() {
  RestorePersistsRotationBeforeUse(); RestoreWithoutStoredSessionDoesNothing(); RejectedRestoreClearsStorage();
  TransientRestoreKeepsStorage(); SignInTriesStoredSessionFirst(); RefreshBeforeRequestIsSingleFlight();
  UnauthorizedRequestRefreshesOnceAndRetries(); RefreshFailuresDuringRequests(); ExpiryKeepsRefreshableSession();
  SignOutClearsAndRevokes(); ShutdownKeepsStorage(); OlderServerStaysMemoryOnly(); StaleGenerationNeverWritesStorage();
  TokenParsing(); AccountLabels(); PlatformStoreRoundTrip();
}
