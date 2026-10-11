#pragma once
#include "account_service.h"
#include "encrypted_blob_store.h"
#include "connect_transport.h"
#include <atomic>
#include <condition_variable>
#include <future>
namespace kelpie::connect {
class Client {
 public:
  using Json=nlohmann::json;
  using Execute=std::function<Json(const Json&,std::shared_ptr<const std::atomic<bool>>)>;
  using Cancel=std::function<void(std::shared_ptr<const std::atomic<bool>>)>;
  using Factory=std::function<std::unique_ptr<Transport>()>;
  Client(account::AccountService& account,const std::filesystem::path& profile,
      std::string platform,std::string installation,Execute execute,Cancel cancel={},Factory factory=MakeTransport);
  ~Client();
  void Update(bool model_ready,bool model_installed=false);
  void Pause(bool paused);
  void Enable(bool enabled);
  void SignOut();
  void UserTabChanged();
  void Shutdown();
  bool Drain();
  std::string Status() const;
  bool paused() const;
  bool enabled() const;
 private:
  void Run();
  void SetStatus(std::string status);
  account::AccountService& account_;
  std::shared_ptr<account::EncryptedBlobStore> journal_,settings_;
  std::string platform_,installation_;
  Execute execute_; Cancel cancel_; Factory factory_;
  mutable std::mutex mutex_; std::condition_variable changed_;
  std::string owner_,status_="Nessie: signed out";
  bool paused_=false,enabled_=true,model_ready_=false,model_installed_=false,working_=false;
  std::atomic<bool> shutdown_{false},discard_{false};
  std::atomic<std::shared_ptr<std::atomic<bool>>> cancelled_{std::make_shared<std::atomic<bool>>(false)};
  std::future<void> worker_;
};
}
