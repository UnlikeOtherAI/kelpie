#pragma once
#include <atomic>
#include <filesystem>
#include <functional>
#include <memory>
#include "account_protocol.h"

namespace kelpie::account {
struct AccountToken { std::string token; double seconds; };
class AccountLogin {
 public:
  AccountLogin();
  ~AccountLogin();
  void Cancel();
  AccountToken Run(const AccountRequest& request, const std::filesystem::path& profile,
                   const std::function<bool(const std::string&)>& open);
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
}  // namespace kelpie::account
