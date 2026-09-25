#include "account_service.h"
#include <httplib.h>
#include <cassert>
#include <condition_variable>
#include <thread>

using namespace kelpie::account;
using json=nlohmann::json;
namespace {
struct FakeServer {
  json list=json::array();
  int puts=0;
  bool conflict=false, deny=false;
  AccountResponse Request(const std::string& path,const std::string& method,const std::string&,
      const std::string& body,const std::string& version) {
    if (deny) throw AccountFailure(401);
    if (path=="/oauth/me") return {R"({"sub":"test-user","email":"test@example.org","name":"Test"})",{}};
    if (path=="/oauth/me/avatar") throw AccountFailure(404);
    assert(path==kAccountBookmarks);
    if (method=="PUT") {
      assert(!version.empty()); ++puts;
      if (conflict && puts==1) {
        list.push_back({{"url","https://other.example/"},{"name","Other device"},{"folder","remote"}});
        throw AccountFailure(409);
      }
      list=json::parse(body).at("value");
    }
    return {json{{"value",list}}.dump(),"\"version\""};
  }
  AccountRequest Transport() { return [this](const auto& p,const auto& m,const auto& t,const auto& b,const auto& v){return Request(p,m,t,b,v);}; }
};
void MergeAndLocalSeparation() {
  kelpie::BookmarkStore local; local.Add("Local","https://local.example/");
  const auto original=local.ToJson();
  FakeServer server;
  server.list={{{"url","https://old.example/"},{"name","Legacy"},{"folder",{{"id",42}}}},"opaque"};
  AccountService account(local,server.Transport());
  account.CompleteSignIn({"test-token",3600},0);
  assert(account.State().signed_in);
  assert(json::parse(account.Bookmarks()).at(0).at("title")=="Legacy");
  server.conflict=true;
  assert(account.BookmarkAction("add",{{"url","https://new.example/"},{"title","New"}}).at("success")==true);
  assert(server.puts==2 && server.list.size()==4);
  assert(server.list.at(0).at("folder").at("id")==42 && server.list.at(1)=="opaque");
  assert(local.ToJson()==original);
  account.BookmarkAction("add",{{"url","https://new.example/"},{"title","Duplicate"}});
  assert(server.list.size()==4);
  auto id=AccountBookmarkID(server.list.at(0));
  for (auto& c:id) c=static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
  account.BookmarkAction("remove",{{"id",id}});
  assert(server.list.size()==3 && server.list.at(0)=="opaque");
  account.SignOut();
  assert(account.Bookmarks()==original && !account.State().signed_in);
}
void SessionFailureAndExpiry() {
  kelpie::BookmarkStore local; local.Add("Local","https://local.example/");
  FakeServer server; AccountService account(local,server.Transport());
  account.CompleteSignIn({"test-token",3600},0);
  server.deny=true;
  const auto response=account.BookmarkAction("add",{{"url","https://never-local.example/"}});
  assert(!response.at("success").get<bool>() && !account.State().signed_in && local.Count()==1);
  server.deny=false;
  account.CompleteSignIn({"test-token",0},1);
  account.Poll();
  assert(!account.State().signed_in && !account.State().error.empty());
}
void LateResponseCannotReplaceLocal() {
  kelpie::BookmarkStore local; local.Add("Local","https://local.example/");
  FakeServer server;
  std::mutex mutex; std::condition_variable cv;
  bool blocked=false,release=false;
  AccountService account(local,[&](const auto& p,const auto& m,const auto& t,const auto& b,const auto& v) {
    if (m=="PUT") {
      std::unique_lock lock(mutex); blocked=true; cv.notify_all(); cv.wait(lock,[&]{return release;});
    }
    return server.Request(p,m,t,b,v);
  });
  account.CompleteSignIn({"test-token",3600},0);
  auto pending=std::async(std::launch::async,[&]{return account.BookmarkAction("add",{{"url","https://cloud.example/"}});});
  { std::unique_lock lock(mutex); cv.wait(lock,[&]{return blocked;}); }
  account.SignOut();
  { std::lock_guard lock(mutex); release=true; cv.notify_all(); }
  assert(!pending.get().at("success").get<bool>());
  assert(account.Bookmarks()==local.ToJson() && local.Count()==1);
}
void CallbackAndPkce() {
  assert(AccountChallenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")=="E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM");
  assert(!SameAccountState("abc","ab") && !SameAccountState("","") && SameAccountState("abc","abc"));
  const auto profile=std::filesystem::temp_directory_path()/RandomAccountValue();
  std::filesystem::create_directories(profile);
  std::string redirect;
  AccountLogin login;
  auto request=[&](const std::string& path,const std::string&,const std::string&,const std::string& body,const std::string&) {
    const auto parsed=json::parse(body);
    if (path=="/oauth/register") {
      redirect=parsed.at("redirect_uris").at(0).get<std::string>();
      return AccountResponse{R"({"client_id":"public-test"})",{}};
    }
    assert(path=="/oauth/token" && parsed.at("code")=="valid-code" && parsed.at("redirect_uri")==redirect);
    return AccountResponse{R"({"access_token":"test-token","token_type":"Bearer","expires_in":3600})",{}};
  };
  auto open=[&](const std::string& url) {
    const auto start=url.find("&state=")+7;
    const auto state=url.substr(start,url.find('&',start)-start);
    const auto end=redirect.find('/',7);
    httplib::Client client(redirect.substr(0,end));
    auto bad=client.Get("/oauth/callback?state=wrong&code=x"); assert(bad && bad->status==400);
    auto duplicate=client.Get("/oauth/callback?state="+state+"&state="+state+"&code=x"); assert(duplicate && duplicate->status==400);
    auto good=client.Get("/oauth/callback?state="+state+"&code=valid-code"); assert(good && good->status==200);
    return true;
  };
  assert(login.Run(request,profile,open).token=="test-token");
  std::filesystem::remove(profile/"uoa-public-client.json"); std::filesystem::remove(profile);
}
void OwnerThreadHandoffAndCancellation() {
  const auto profile=std::filesystem::temp_directory_path()/RandomAccountValue();
  std::filesystem::create_directories(profile);
  kelpie::BookmarkStore local;
  std::mutex mutex; std::condition_variable cv;
  bool registering=false,release=false;
  AccountService account(local,[&](const auto& path,const auto&,const auto&,const auto&,const auto&) {
    assert(path=="/oauth/register");
    std::unique_lock lock(mutex); registering=true; cv.notify_all();
    cv.wait(lock,[&]{return release;});
    return AccountResponse{R"({"client_id":"public-handoff"})",{}};
  });
  int opened=0;
  const auto owner=std::this_thread::get_id();
  auto open=[&](const std::string& url) {
    assert(std::this_thread::get_id()==owner && url.starts_with(kAccountOrigin));
    ++opened; return true;
  };
  assert(account.StartSignIn(profile,open));
  { std::unique_lock lock(mutex); cv.wait(lock,[&]{return registering;}); }
  assert(!account.StartSignIn(profile,open));
  account.SignOut();
  { std::lock_guard lock(mutex); release=true; cv.notify_all(); }
  const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(5);
  while(!account.Drain() && std::chrono::steady_clock::now()<deadline) std::this_thread::sleep_for(std::chrono::milliseconds(1));
  assert(account.Drain()); account.Poll(); assert(opened==0);
  assert(account.StartSignIn(profile,open));
  while(opened==0 && std::chrono::steady_clock::now()<deadline) {
    account.Poll(); std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  assert(opened==1);
  account.Poll(); assert(opened==1); // Consumed once, including repeated toolbar clicks.
  account.SignOut();
  while(!account.Drain() && std::chrono::steady_clock::now()<deadline) std::this_thread::sleep_for(std::chrono::milliseconds(1));
  assert(account.Drain());
  assert(account.StartSignIn(profile,[](const std::string&) { return false; }));
  while(account.State().signing_in && std::chrono::steady_clock::now()<deadline) {
    account.Poll(); std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  assert(!account.State().signing_in && !account.State().error.empty());
  account.Shutdown();
  while(!account.Drain() && std::chrono::steady_clock::now()<deadline) std::this_thread::sleep_for(std::chrono::milliseconds(1));
  assert(account.Drain());
  std::filesystem::remove(profile/"uoa-public-client.json"); std::filesystem::remove(profile);
}
void EarlyCancellationDoesNotHang() {
  const auto profile=std::filesystem::temp_directory_path()/RandomAccountValue();
  std::filesystem::create_directories(profile);
  for(int i=0;i<30;++i) {
    AccountLogin login;
    auto pending=std::async(std::launch::async,[&] {
      try {
        login.Run([](const auto&,const auto&,const auto&,const auto&,const auto&) {
          return AccountResponse{R"({"client_id":"public-cancel"})",{}};
        },profile,[](const std::string&) { return false; });
      } catch(const AccountFailure&) {}
    });
    if(i%2) std::this_thread::sleep_for(std::chrono::milliseconds(1));
    login.Cancel();
    assert(pending.wait_for(std::chrono::seconds(3))==std::future_status::ready);
    pending.get();
  }
  std::filesystem::remove(profile/"uoa-public-client.json"); std::filesystem::remove(profile);
}
}
int main() {
  MergeAndLocalSeparation(); SessionFailureAndExpiry(); LateResponseCannotReplaceLocal(); CallbackAndPkce();
  OwnerThreadHandoffAndCancellation(); EarlyCancellationDoesNotHang();
}
