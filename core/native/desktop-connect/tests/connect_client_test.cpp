#include "connect_client.h"
#include <cassert>
#include <cstdio>
#undef assert
#define assert(v) do { if(!(v)) { std::fprintf(stderr,"Assertion failed at line %d: %s\n",__LINE__,#v);std::abort(); } } while(false)
#include <deque>
#include <iomanip>
#include <sstream>
#include <thread>
using namespace kelpie;
using namespace kelpie::connect;
using Json=nlohmann::json;
namespace {
constexpr char kGeneration[]="10000000-0000-4000-8000-000000000001";
constexpr char kDevice[]="10000000-0000-4000-8000-000000000002";
constexpr char kJob[]="10000000-0000-4000-8000-000000000003";
constexpr char kAttempt[]="10000000-0000-4000-8000-000000000004";
std::string Deadline() {
  const auto value=std::chrono::system_clock::to_time_t(std::chrono::system_clock::now()+std::chrono::minutes(5));
  std::tm utc{};
#ifdef _WIN32
  gmtime_s(&utc,&value);
#else
  gmtime_r(&value,&utc);
#endif
  std::ostringstream output;output<<std::put_time(&utc,"%Y-%m-%dT%H:%M:%S.000Z");return output.str();
}
struct Wire {
  std::mutex mutex;
  std::deque<std::string> incoming;
  std::vector<Json> sent;
  bool command=true,disconnect=false,control_v1=false;
};
class Socket final:public Transport {
 public:
  explicit Socket(std::shared_ptr<Wire> wire):wire_(std::move(wire)) {}
  void Open()override {}
  void Send(const std::string& raw)override {
    const auto frame=Json::parse(raw);std::lock_guard lock(wire_->mutex);wire_->sent.push_back(frame);
    if(frame["type"]=="hello") {
      assert(frame["ticket"]=="scoped" && !frame.contains("access_token"));
      auto capabilities=Json::array({"browser.control"});if(wire_->control_v1)capabilities.push_back("browser.control.v1");capabilities.push_back("page.extract");
      assert(frame["capabilities"]==capabilities && !frame["label"].get<std::string>().empty());
      wire_->incoming.push_back(Json{{"type","welcome"},{"protocol",1},{"generation",kGeneration},{"deviceId",kDevice}}.dump());
      if(wire_->command)wire_->incoming.push_back(Json{{"type","command"},{"generation",kGeneration},{"jobId",kJob},{"attemptId",kAttempt},
          {"seq",1},{"deadline",Deadline()},{"operation","click"},{"tabId","owned"},{"tabVersion","document"},{"input",{{"selector","#go"}}}}.dump());
    }
  }
  std::optional<std::string> Receive(std::chrono::milliseconds)override {
    { std::lock_guard lock(wire_->mutex);if(!wire_->incoming.empty()) { auto frame=std::move(wire_->incoming.front());wire_->incoming.pop_front();return frame; }
      if(wire_->disconnect) { for(const auto& frame:wire_->sent)if(frame["type"]=="event" && frame["state"]=="accepted") { wire_->disconnect=false;throw std::runtime_error("Disconnected"); } } }
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
  first->control_v1=true;
  {
    Client client(account,profile,"windows",kDevice,execute,{},[first] { return std::make_unique<Socket>(first); },true);
    client.Update(false);assert(Wait([&] { return Terminal(first); }));assert(effects==1);
    client.Pause(true);assert(client.paused());client.Shutdown();assert(Wait([&] { return client.Drain(); }));
  }
  const auto interrupted_profile=std::filesystem::temp_directory_path()/account::RandomAccountValue();
  auto interrupted=std::make_shared<Wire>();interrupted->disconnect=true;std::atomic<bool> stopped=false;
  {
    Client client(account,interrupted_profile,"windows",kDevice,[&](const Json&,std::shared_ptr<const std::atomic<bool>> guard) {
      assert(Wait([&] { return guard->load(); }));stopped=true;return Json{{"state","cancelled"},{"error","Connection lost"}};
    },{},[interrupted] { return std::make_unique<Socket>(interrupted); });
    client.Update(false);assert(Wait([&] { return stopped.load(); }));
    assert(Wait([&] { std::lock_guard lock(interrupted->mutex);int count=0;for(const auto& frame:interrupted->sent)if(frame["type"]=="hello")++count;return count>=2; }));
    client.Shutdown();assert(Wait([&] { return client.Drain(); }));
  }
  std::filesystem::remove_all(interrupted_profile);
  const auto cancelling_profile=std::filesystem::temp_directory_path()/account::RandomAccountValue();
  auto cancellation=std::make_shared<Wire>();std::atomic<bool> started=false,done=false;
  std::atomic<int> cancellations=0;
  {
    Client client(account,cancelling_profile,"windows",kDevice,[&](const Json&,std::shared_ptr<const std::atomic<bool>> guard) {
      started=true;assert(Wait([&] { return guard->load(); }));done=true;
      return Json{{"state","cancelled"},{"error","Own attempt stopped"}};
    },[&](const auto& guard) { assert(guard->load());++cancellations; },[cancellation] { return std::make_unique<Socket>(cancellation); });
    client.Update(false);assert(Wait([&] { return started.load(); }));
    const auto cancel_frame=[&](const char* job,const char* attempt) {
      std::lock_guard lock(cancellation->mutex);
      cancellation->incoming.push_back(Json{{"type","cancel"},{"generation",kGeneration},{"jobId",job},
          {"attemptId",attempt},{"seq",2}}.dump());
    };
    constexpr auto other="10000000-0000-4000-8000-000000000009";
    cancel_frame(other,other);
    assert(Wait([&] { std::lock_guard lock(cancellation->mutex);for(const auto& frame:cancellation->sent)
      if(frame["type"]=="event" && frame["jobId"]==other && frame["state"]=="cancelled")return true;return false; }));
    assert(!done && cancellations==0); // Receipt for queued work cannot stop the active job.
    cancel_frame(kJob,kAttempt);assert(Wait([&] { return done.load(); }));
    assert(cancellations>=1);
    client.Shutdown();assert(Wait([&] { return client.Drain(); }));
  }
  std::filesystem::remove_all(cancelling_profile);
  const auto resume_profile=std::filesystem::temp_directory_path()/account::RandomAccountValue();
  auto resumed=std::make_shared<Wire>();std::mutex guards_mutex;
  std::vector<std::shared_ptr<const std::atomic<bool>>> guards;
  std::atomic<bool> callback_waiting=false,release_callback=false;
  {
    Client client(account,resume_profile,"windows",kDevice,[&](const Json&,const auto& guard) {
      { std::lock_guard lock(guards_mutex);guards.push_back(guard); }
      assert(Wait([&] { return guard->load(); }));return Json{{"state","cancelled"}};
    },[&](const auto& guard) {
      if(!callback_waiting.exchange(true)) {
        assert(guard->load());assert(Wait([&] { return release_callback.load(); }));
        std::lock_guard lock(guards_mutex);assert(guards.size()==2);
        assert(guard==guards[0] && guard!=guards[1] && !guards[1]->load());
      }
    },[resumed] { return std::make_unique<Socket>(resumed); });
    client.Update(false);assert(Wait([&] { std::lock_guard lock(guards_mutex);return guards.size()==1; }));
    auto pausing=std::async(std::launch::async,[&] { client.Pause(true); });
    assert(Wait([&] { return callback_waiting.load(); }));client.Pause(false);
    constexpr auto next="10000000-0000-4000-8000-000000000008";
    { std::lock_guard lock(resumed->mutex);resumed->incoming.push_back(Json{{"type","command"},
      {"generation",kGeneration},{"jobId",next},{"attemptId",next},{"seq",1},{"deadline",Deadline()},
      {"operation","click"},{"tabId","owned"},{"tabVersion","document"},{"input",{{"selector","#next"}}}}.dump()); }
    assert(Wait([&] { std::lock_guard lock(guards_mutex);return guards.size()==2; }));
    release_callback=true;pausing.get();client.Shutdown();assert(Wait([&] { return client.Drain(); }));
  }
  std::filesystem::remove_all(resume_profile);
  auto second=std::make_shared<Wire>();
  {
    Client client(account,profile,"windows",kDevice,execute,{},[second] { return std::make_unique<Socket>(second); });
    assert(client.paused()); // Restore controls before restored account becomes available.
    std::this_thread::sleep_for(std::chrono::milliseconds(350));client.Update(false);
    assert(Wait([&] { return Terminal(second); }));assert(effects==1); // Same attempt is replayed, never rerun.
    client.Enable(false);assert(!client.enabled());client.SignOut();account.SignOut();
    assert(Wait([&] { return !std::filesystem::exists(profile/"nessie.journal.v1"); }));
    client.Shutdown();assert(Wait([&] { return client.Drain(); }));
  }
  std::filesystem::remove_all(profile);
}
