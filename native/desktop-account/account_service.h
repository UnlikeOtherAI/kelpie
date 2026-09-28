#pragma once
#include <chrono>
#include <future>
#include <mutex>
#include <optional>
#include <vector>
#include "account_login.h"
#include "account_session_store.h"
#include "account_state.h"
#include "kelpie/bookmark_store.h"

namespace kelpie::account {
class AccountService {
 public:
  explicit AccountService(BookmarkStore& local, AccountRequest request={},
      std::shared_ptr<AccountSessionStore> store=std::make_shared<MemoryAccountSessionStore>());
  ~AccountService();
  AccountState State() const;
  std::string Bookmarks() const; // Memory only; safe on CEF's IO thread.
  nlohmann::json BookmarkAction(const std::string& action,const nlohmann::json& params, std::optional<std::uint64_t> expected={});
  // Launch restore: signs in from the stored session in the background. False when none is stored.
  bool RestoreSession();
  // Tries the stored session first; a rejected one falls through to interactive login.
  bool StartSignIn(const std::filesystem::path& profile,const std::function<bool(const std::string&)>& open);
  bool StartBookmarkAction(std::string action,nlohmann::json params={});
  // User sign-out or cancel: clears memory and the stored session, then revokes it in the background.
  void SignOut();
  void Poll();
  // App exit: stops account work but keeps the stored session for the next launch.
  void Shutdown();
  bool Drain();
  // A completed authenticated session, also exercised with the injectable transport.
  void CompleteSignIn(const AccountToken& token,std::uint64_t generation);
 private:
  struct PendingRevoke { std::shared_ptr<AccountTransport> transport; std::future<void> done; };
  bool StartTask(std::function<void(std::uint64_t)> task,bool login);
  void Fail(std::uint64_t generation,const std::string& message,int status=0);
  void ExpireSession(std::uint64_t generation,const std::string& message);
  void CheckGeneration(std::uint64_t generation) const;
  AccountRequest RequestLocked() const;
  AccountRequest Request() const;
  // Session lifecycle (account_service_session.cpp).
  AccountSession Reset();
  bool ResumeStoredSession(const AccountSession& session,std::uint64_t generation);
  void InteractiveSignIn(const std::filesystem::path& profile,std::uint64_t generation);
  bool AdoptToken(const AccountToken& token,std::uint64_t generation);
  std::string AccessToken(std::uint64_t generation,const std::string& rejected={});
  AccountResponse Authorized(std::uint64_t generation,const std::string& path,const std::string& method,
      const std::string& body={},const std::string& version={});
  // *Locked storage helpers require store_mutex_; store failures never escape.
  std::optional<AccountSession> LoadStoredLocked();
  void ClearStoredLocked();
  void DiscardStoredSession(std::uint64_t generation);
  void Revoke(const AccountSession& session);
  void PruneRevokesLocked();
  BookmarkStore& local_;
  std::shared_ptr<AccountTransport> transport_=std::make_shared<AccountTransport>();
  AccountRequest request_;
  std::shared_ptr<AccountSessionStore> store_;
  // Lock order: operation_ -> refresh_ -> store_mutex_ -> mutex_.
  mutable std::mutex mutex_;
  std::timed_mutex operation_;
  std::mutex refresh_;      // Single-flight token refresh.
  std::mutex store_mutex_;  // Serializes storage with the generation check that guards it.
  AccountState state_;
  std::uint64_t generation_=0;
  std::string token_, refresh_token_, client_id_;
  nlohmann::json bookmarks_=nlohmann::json::array();
  std::chrono::steady_clock::time_point expiry_{};
  std::shared_ptr<AccountLogin> login_;
  std::function<bool(const std::string&)> open_browser_;
  std::string pending_browser_url_;
  std::future<void> task_;
  std::vector<PendingRevoke> revokes_;
};
}  // namespace kelpie::account
