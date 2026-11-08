#pragma once
#include <functional>
#include <mutex>
#include <stdexcept>
#include <string>


namespace kelpie::account {
// Embedded hosts use the same fixed-origin, cancellable transport without a public OAuth identity.
inline bool IsAccountTransportPath(const std::string& path) {
  if (path.find("..") != std::string::npos) return false;
  return path.starts_with("/oauth/") || path == "/embedded/kelpie/me" ||
      path == "/embedded/kelpie/me/avatar" || path == "/embedded/kelpie/me/settings/browser/bookmarks" ||
      path == "/embedded/kelpie/connect";
}

struct AccountResponse { std::string body, version; };
struct AccountFailure : std::runtime_error {
  int status;
  explicit AccountFailure(int code) : AccountFailure(code, code == 401
      ? "Your UOA session expired. Sign in again."
      : code == 403 ? "UOA did not grant access to favorites."
      : "UOA could not complete this request. Please try again.") {}
  AccountFailure(int code, const std::string& message) : std::runtime_error(message), status(code) {}
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
