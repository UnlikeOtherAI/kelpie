#pragma once
#include <functional>
#include <mutex>
#include <stdexcept>
#include <string>


namespace kelpie::account {
struct AccountResponse { std::string body, version; };
struct AccountFailure : std::runtime_error {
  int status;
  explicit AccountFailure(int code) : std::runtime_error(code == 401
      ? "Your UOA session expired. Sign in again."
      : code == 403 ? "UOA did not grant access to favorites."
      : "UOA could not complete this request. Please try again."), status(code) {}
};
using AccountRequest = std::function<AccountResponse(const std::string&, const std::string&,
    const std::string&, const std::string&, const std::string&)>;

// Fixed TLS origin, no cookies/redirects/cache, cancellable bounded requests.
class AccountTransport {
 public:
  AccountResponse Request(const std::string& path, const std::string& method,
      const std::string& token = {}, const std::string& body = {}, const std::string& version = {});
  void Cancel();
 private:
  std::mutex mutex_;
  void* active_ = nullptr;
  unsigned generation_ = 0;
  bool cancelled_ = false;
};
}  // namespace kelpie::account
