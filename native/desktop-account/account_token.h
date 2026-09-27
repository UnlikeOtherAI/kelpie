#pragma once
#include <string>
#include "account_transport.h"

namespace kelpie::account {
inline constexpr char kAccountUnreachable[] = "Could not reach UOA. Please try again.";

// One UOA token response. refresh_token is empty when the server issued none
// (older UOA), which keeps the session memory-only.
struct AccountToken {
  std::string token;
  double seconds = 0;
  std::string refresh_token, client_id;
};

// The only durable UOA credential: a rotating refresh token and the public
// client it is bound to. Never profile data.
struct AccountSession {
  std::string client_id, refresh_token;
  bool operator==(const AccountSession&) const = default;
};

// Validates a /oauth/token success body. Throws AccountFailure(403) for a grant
// Kelpie cannot use and a JSON exception for an unparseable body.
AccountToken ParseAccountToken(const std::string& body, const std::string& client);

// Rotates a stored session. A rejected token (400/401/403 or an unusable grant)
// throws AccountFailure(401); anything transient throws AccountFailure(0).
AccountToken RefreshAccountToken(const AccountRequest& request, const AccountSession& session);

// RFC 7009 best effort: every failure, including an older server's 404, is ignored.
void RevokeAccountToken(const AccountRequest& request, const AccountSession& session) noexcept;
}  // namespace kelpie::account
