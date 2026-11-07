#pragma once
#include <filesystem>
#include <memory>
#include <optional>
#include <string>
#include "account_token.h"

namespace kelpie::account {
inline constexpr char kAccountSessionKey[] = "uoa.session.v1";

// Encrypted persistence for {client_id, refresh_token} under kAccountSessionKey.
// AccountService serializes every call, so implementations need no locking.
class AccountSessionStore {
 public:
  virtual ~AccountSessionStore() = default;
  // Missing, corrupt or undecryptable data is no session; unusable data is deleted.
  virtual std::optional<AccountSession> Load() = 0;
  // Atomically replaces the stored session; false when it could not be written.
  virtual bool Save(const AccountSession& session) = 0;
  virtual void Clear() = 0;
};

// Process-lifetime store used when no platform store is injected.
class MemoryAccountSessionStore final : public AccountSessionStore {
 public:
  std::optional<AccountSession> Load() override { return session_; }
  bool Save(const AccountSession& session) override { session_ = session; return true; }
  void Clear() override { session_.reset(); }
 private:
  std::optional<AccountSession> session_;
};

// The platform secret store inside a per-user profile directory: DPAPI on
// Windows, AES-256-GCM with a separate 0600 key file elsewhere.
std::shared_ptr<AccountSessionStore> MakeAccountSessionStore(const std::filesystem::path& directory);

std::string EncodeAccountSession(const AccountSession& session);
std::optional<AccountSession> DecodeAccountSession(const std::string& text);
}  // namespace kelpie::account
