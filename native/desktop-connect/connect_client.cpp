#include "connect_client.h"
#include "kelpie/connect.h"
#include <algorithm>
#include <thread>
namespace kelpie::connect {
using Json=nlohmann::json;
Client::Client(account::AccountService& account,const std::filesystem::path& profile,
    std::string platform,std::string installation,Execute execute,std::function<void()> cancel,Factory factory)
    :account_(account),journal_(account::MakeEncryptedBlobStore(profile,"nessie.journal.v1",32*1024*1024)),
     settings_(account::MakeEncryptedBlobStore(profile,"nessie.controls.v1",4096)),platform_(std::move(platform)),
     installation_(std::move(installation)),execute_(std::move(execute)),cancel_(std::move(cancel)),factory_(std::move(factory)) {
  try { if(auto raw=settings_->Load()) {
    const auto value=Json::parse(*raw,nullptr,false);
    if(value.is_object()) { enabled_=value.value("enabled",true); paused_=value.value("paused",false); }
  }
  } catch(...) { enabled_=false; status_="Nessie: storage unavailable"; }
  worker_=std::async(std::launch::async,[this] { Run(); });
}
Client::~Client() { Shutdown(); if(worker_.valid())worker_.wait(); }
void Client::Update(bool ready) {
  const auto owner=account_.ConnectionOwner();
  std::lock_guard lock(mutex_);
  if(owner!=owner_) { if(!owner_.empty())discard_=true; cancelled_.load()->store(true); owner_=owner; changed_.notify_all(); }
  model_ready_=ready;
}
void Client::Pause(bool value) {
  { std::lock_guard lock(mutex_); paused_=value; if(value)cancelled_.load()->store(true); if(!settings_->Save(Json{{"enabled",enabled_},{"paused",paused_}}.dump())) { enabled_=false; status_="Nessie: storage unavailable"; } }
  if(value && cancel_)cancel_(); changed_.notify_all();
}
void Client::Enable(bool value) {
  { std::lock_guard lock(mutex_); enabled_=value; if(!value)cancelled_.load()->store(true); if(!settings_->Save(Json{{"enabled",enabled_},{"paused",paused_}}.dump())) { enabled_=false; status_="Nessie: storage unavailable"; } }
  if(!value && cancel_)cancel_(); changed_.notify_all();
}
void Client::SignOut() { { std::lock_guard lock(mutex_); owner_.clear(); discard_=true; cancelled_.load()->store(true); } if(cancel_)cancel_(); changed_.notify_all(); }
void Client::Shutdown() { shutdown_=true; cancelled_.load()->store(true); if(cancel_)cancel_(); changed_.notify_all(); }
bool Client::Drain() { return !worker_.valid() || worker_.wait_for(std::chrono::seconds(0))==std::future_status::ready; }
void Client::SetStatus(std::string value) { std::lock_guard lock(mutex_); status_=std::move(value); }
std::string Client::Status() const { std::lock_guard lock(mutex_); return status_; }
bool Client::paused() const { std::lock_guard lock(mutex_); return paused_; }
bool Client::enabled() const { std::lock_guard lock(mutex_); return enabled_; }

void Client::Run() {
  using Clock=std::chrono::steady_clock;
  std::unique_ptr<KelpieConnect,decltype(&kelpie_connect_destroy)> ledger(nullptr,kelpie_connect_destroy);
  std::string ledger_owner,generation; std::future<Json> task; Json active;
  auto persist=[&](const char* operation,const Json& body) {
    std::unique_ptr<char,decltype(&kelpie_connect_free)> result(kelpie_connect_execute(ledger.get(),operation,body.dump().c_str()),kelpie_connect_free);
    if(!result)throw std::runtime_error("Invalid gateway message");
    const auto value=Json::parse(result.get());
    if(!journal_->Save(value.at("state").dump())) { std::lock_guard lock(mutex_); enabled_=false; throw std::runtime_error("Connection journal unavailable"); }
    return value.at("decision");
  };
  auto finish=[&]() {
    if(task.valid() && task.wait_for(std::chrono::seconds(0))==std::future_status::ready) {
      auto result=task.get(); result["jobId"]=active.at("jobId"); result["attemptId"]=active.at("attemptId");
      return persist("complete",result);
    }
    return Json::object();
  };
  unsigned failures=0;
  while(!shutdown_) {
    std::string owner; bool enabled,paused,ready;
    { std::unique_lock lock(mutex_); owner=owner_; enabled=enabled_; paused=paused_; ready=model_ready_;
      if(owner.empty() || !enabled) {
        status_=owner.empty()?"Nessie: signed out":"Nessie: stopped";
        if(discard_ && !task.valid()) { journal_->Clear(); ledger.reset(); ledger_owner.clear(); discard_=false; }
        changed_.wait_for(lock,std::chrono::milliseconds(250));
      }
    }
    try {
      if(task.valid())finish();
      if(discard_) { if(task.valid())continue; journal_->Clear(); ledger.reset(); ledger_owner.clear(); discard_=false; }
      if(owner.empty() || !enabled)continue;
      if(owner!=ledger_owner) {
        if(task.valid()) { cancelled_.load()->store(true); std::this_thread::sleep_for(std::chrono::milliseconds(50)); continue; }
        std::string saved;
        try { saved=journal_->Load().value_or(""); } catch(...) { std::lock_guard lock(mutex_); enabled_=false; throw; }
        ledger.reset(kelpie_connect_create(saved.c_str(),owner.c_str())); ledger_owner=owner;
        if(!ledger)throw std::runtime_error("Connection journal unavailable");
      }
      auto ticket=account_.ConnectionTicket();
      { std::lock_guard lock(mutex_); if(owner!=owner_ || !enabled_)continue; }
      auto socket=factory_(); socket->Open(); generation.clear();
      auto caps=Json::array({"tabs","open","navigate","snapshot","click","type","scroll","back","forward","reload"});
      if(ready)caps.push_back("extract");
      socket->Send(Json{{"type","hello"},{"protocol",1},{"ticket",ticket.at("connection_ticket")},
          {"installationId",installation_},{"label","Kelpie "+platform_},{"platform",platform_},
          {"capabilities",caps},{"lifecycle",paused?"paused":"ready"},{"modelReady",ready},{"modelInstalled",ready},{"modelCapabilities",ready?Json::array({"text"}):Json::array()},{"delegatedBrowsing",false}}.dump());
      auto expiry=Clock::now()+std::chrono::milliseconds(static_cast<int>(ticket.at("expires_in").get<double>()*1000));
      auto renewal=Clock::now()+std::chrono::milliseconds(std::min(60000,static_cast<int>(ticket.at("expires_in").get<double>()*500)));
      const auto advertised_ready=ready;
      auto beat=Clock::now(); const auto welcome_deadline=Clock::now()+std::chrono::seconds(10);
      auto send=[&](const Json& decision) { for(const auto& frame:decision.value("frames",Json::array()))socket->Send(frame.dump()); };
      while(!shutdown_) {
        { std::lock_guard lock(mutex_); if(owner!=owner_ || !enabled_ || advertised_ready!=model_ready_)break; paused=paused_; ready=model_ready_; }
        if(Clock::now()>=expiry)throw std::runtime_error("Connection ticket expired");
        if(generation.empty() && Clock::now()>welcome_deadline)throw std::runtime_error("Gateway unavailable");
        if(!generation.empty() && Clock::now()>=renewal) {
          ticket=account_.ConnectionTicket();
          socket->Send(Json{{"type","auth"},{"generation",generation},{"ticket",ticket.at("connection_ticket")}}.dump());
          expiry=Clock::now()+std::chrono::milliseconds(static_cast<int>(ticket.at("expires_in").get<double>()*1000));
          renewal=Clock::now()+std::chrono::milliseconds(std::min(60000,static_cast<int>(ticket.at("expires_in").get<double>()*500)));
        }
        if(!task.valid() && !generation.empty())SetStatus(paused?"Nessie: paused":"Nessie: connected");
        if(!generation.empty() && Clock::now()>=beat) {
          socket->Send(Json{{"type","heartbeat"},{"generation",generation},{"lifecycle",paused?"paused":"ready"},{"modelReady",ready},{"modelInstalled",ready},{"modelCapabilities",ready?Json::array({"text"}):Json::array()},{"delegatedBrowsing",false}}.dump());
          beat=Clock::now()+std::chrono::seconds(5);
        }
        send(finish());
        const auto raw=socket->Receive(std::chrono::milliseconds(100)); if(!raw)continue;
        const auto frame=Json::parse(*raw);
        if(frame.value("type","")=="auth_ok" || frame.value("type","")=="heartbeat_ack")continue;
        const auto decision=persist("receive",frame); send(decision);
        const auto kind=decision.value("kind","");
        if(kind=="welcome") { generation=frame.at("generation"); failures=0; SetStatus(paused?"Nessie: paused":"Nessie: connected"); }
        if(kind=="cancel") { cancelled_.load()->store(true); if(cancel_)cancel_(); }
        if(kind=="command") {
          const auto command=decision.at("command");
          if(paused || task.valid()) { send(persist("complete",Json{{"jobId",command.at("jobId")},{"attemptId",command.at("attemptId")},
              {"state","failed"},{"error",paused?"DEVICE_PAUSED":"DEVICE_BUSY"}})); continue; }
          active=command; cancelled_.store(std::make_shared<std::atomic<bool>>(false)); SetStatus("Nessie: working — "+command.at("operation").get<std::string>());
          task=std::async(std::launch::async,[this,command,guard=cancelled_.load()] {
            try { return execute_(command,guard); } catch(...) { return Json{{"state","failed"},{"error","Operation failed; reconcile page before retry"}}; }
          });
        }
        if(!task.valid() && !generation.empty())SetStatus(paused?"Nessie: paused":"Nessie: connected");
      }
      socket->Close();
    }catch(const account::AccountFailure& failure) {
      SetStatus(failure.status==403?"Nessie: sign in again to allow connection":failure.status==401?"Nessie: signed out":"Nessie: waiting for UOA");
      if(failure.status==403) { std::unique_lock lock(mutex_); changed_.wait_for(lock,std::chrono::seconds(30)); }
    }catch(...) { SetStatus("Nessie: reconnecting"); }
    if(!shutdown_) { std::unique_lock lock(mutex_); changed_.wait_for(lock,std::chrono::seconds(std::min(30u,1u<<std::min(failures++,5u)))); }
  }
  if(task.valid()) { cancelled_.load()->store(true); task.wait(); try { finish(); } catch(...) {} }
}
}
