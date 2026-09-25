#pragma once
#include <chrono>
#include <future>
#include <mutex>
#include <optional>
#include "account_login.h"
#include "account_state.h"
#include "kelpie/bookmark_store.h"

namespace kelpie::account {
class AccountService {
 public:
  explicit AccountService(BookmarkStore& local, AccountRequest request={});
  ~AccountService();
  AccountState State() const;
  std::string Bookmarks() const; // Memory only; safe on CEF's IO thread.
  nlohmann::json BookmarkAction(const std::string& action,const nlohmann::json& params, std::optional<std::uint64_t> expected={});
  bool StartSignIn(const std::filesystem::path& profile,const std::function<bool(const std::string&)>& open);
  bool StartBookmarkAction(std::string action,nlohmann::json params={});
  void SignOut();
  void Poll();
  void Shutdown();
  bool Drain();
  // A completed authenticated session, also exercised with the injectable transport.
  void CompleteSignIn(const AccountToken& token,std::uint64_t generation);
 private:
  bool StartTask(std::function<void(std::uint64_t)> task,bool login);
  void Fail(std::uint64_t generation,const std::string& message,int status=0);
  void CheckGeneration(std::uint64_t generation) const;
  BookmarkStore& local_;
  std::shared_ptr<AccountTransport> transport_=std::make_shared<AccountTransport>();
  AccountRequest RequestLocked() const;
  AccountRequest request_;
  mutable std::mutex mutex_;
  std::timed_mutex operation_;
  AccountState state_;
  std::uint64_t generation_=0;
  std::string token_;
  nlohmann::json bookmarks_=nlohmann::json::array();
  std::chrono::steady_clock::time_point expiry_{};
  std::shared_ptr<AccountLogin> login_;
  std::function<bool(const std::string&)> open_browser_;
  std::string pending_browser_url_;
  std::future<void> task_;
};
}  // namespace kelpie::account
