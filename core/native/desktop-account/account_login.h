#pragma once
#include <atomic>
#include <filesystem>
#include <functional>
#include <memory>
#include "account_protocol.h"
#include "account_token.h"

namespace kelpie::account {
class AccountLogin {
 public:
  AccountLogin();
  ~AccountLogin();
  void Cancel();
  // Returns the exchanged token with the registered client_id and, from a
  // refresh-capable UOA server, its refresh token.
  AccountToken Run(const AccountRequest& request, const std::filesystem::path& profile,
                   const std::function<bool(const std::string&)>& open);
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
}  // namespace kelpie::account
