#include "connect_client.h"
#include <cassert>
#include <deque>
#include <thread>
using namespace kelpie;
using namespace kelpie::connect;
namespace {
constexpr char kGeneration[]="10000000-0000-4000-8000-000000000001";
constexpr char kDevice[]="10000000-0000-4000-8000-000000000002";
constexpr char kJob[]="10000000-0000-4000-8000-000000000003";
constexpr char kAttempt[]="10000000-0000-4000-8000-000000000004";
struct Wire {
  std::mutex mutex;
  std::deque<std::string> incoming;
  std::vector<Json> sent;
  bool command=true;
};
class Socket final:public Transport {
 public:
  explicit Socket(std::shared_ptr<Wire> wire):wire_(std::move(wire)) {}
  void Open()override {}
  void Send(const std::string& raw)override {
    const auto frame=Json::parse(raw);std::lock_guard lock(wire_->mutex);wire_->sent.push_back(frame);
    if(frame["type"]=="hello") {
      assert(frame["ticket"]=="scoped" && !frame.contains("access_token"));
      wire_->incoming.push_back(Json{{"type","welcome"},{"protocol",1},{"generation",kGeneration},{"deviceId",kDevice}}.dump());
      if(wire_->command)wire_->incoming.push_back(Json{{"type","command"},{"generation",kGeneration},{"jobId",kJob},{"attemptId",kAttempt},
          {"seq",1},{"deadline","2099-10-11T12:00:00.000Z"},{"operation","click"},{"tabId","owned"},{"tabVersion","document"},{"input",{{"selector","#go"}}}}.dump());
    }
  }
  std::optional<std::string> Receive(std::chrono::milliseconds)override {
    { std::lock_guard lock(wire_->mutex);if(!wire_->incoming.empty()) { auto frame=std::move(wire_->incoming.front());wire_->incoming.pop_front();return frame; } }
    std::this_thread::sleep_for(std::chrono::milliseconds(10));return {};
  }
  void Close()override {}
 private:
  std::shared_ptr<Wire> wire_;
};
bool Wait(const std::function<bool()>& predicate) {
  for(int i=0;i<300;++i) { if(predicate())return true;std::this_thread::sleep_for(std::chrono::milliseconds(10)); }return false;
}
bool Terminal(const std::shared_ptr<Wire>& wire) {
  std::lock_guard lock(wire->mutex);for(const auto& frame:wire->sent)if(frame["type"]=="event" && frame["state"]=="completed")return frame["seq"]==2;return false;
}
}
int main() {
  const auto profile=std::filesystem::temp_directory_path()/account::RandomAccountValue();
  BookmarkStore bookmarks;
  account::AccountService account(bookmarks,[](const auto& path,const auto&,const auto&,const auto&,const auto&) -> account::AccountResponse {
    if(path=="/oauth/me")return {R"({"sub":"owner","email":"owner@example.org"})",{}};
    if(path==account::kAccountBookmarks)return {R"({"value":[]})",{}};
    if(path=="/oauth/me/avatar")throw account::AccountFailure(404);
    if(path=="/oauth/revoke")return {"{}",{}};
    assert(path=="/oauth/kelpie/connect");return {R"({"connection_ticket":"scoped","token_type":"Bearer","expires_in":120,"gateway_url":"wss://api.nessie.works/api/kelpie/connect"})",{}};
  });
  account.CompleteSignIn({"broad",3600,"refresh","client"},0);
  std::atomic<int> effects=0;
  auto execute=[&](const Json&,std::shared_ptr<const std::atomic<bool>>) {
    const auto saved=account::MakeEncryptedBlobStore(profile,"nessie.journal.v1",32*1024*1024)->Load();
    assert(saved && Json::parse(*saved)["jobs"].size()==1); // Reservation is already durable.
    ++effects;return Json{{"state","completed"},{"output",{{"success",true}}}};
  };
  auto first=std::make_shared<Wire>();
  {
    Client client(account,profile,"windows",kDevice,execute,{},[first] { return std::make_unique<Socket>(first); });
    client.Update(false);assert(Wait([&] { return Terminal(first); }));assert(effects==1);
    client.Pause(true);assert(client.paused());client.Shutdown();assert(Wait([&] { return client.Drain(); }));
  }
  auto second=std::make_shared<Wire>();
  {
    Client client(account,profile,"windows",kDevice,execute,{},[second] { return std::make_unique<Socket>(second); });
    assert(client.paused()); // Restore controls before restored account becomes available.
    std::this_thread::sleep_for(std::chrono::milliseconds(350));client.Update(false);
    assert(Wait([&] { return Terminal(second); }));assert(effects==1); // Same attempt is replayed, never rerun.
    client.Enable(false);assert(!client.enabled());client.SignOut();account.SignOut();
    assert(Wait([&] { return !account::MakeEncryptedBlobStore(profile,"nessie.journal.v1",32*1024*1024)->Load(); }));
    client.Shutdown();assert(Wait([&] { return client.Drain(); }));
  }
  std::filesystem::remove_all(profile);
}
