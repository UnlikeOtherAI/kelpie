#include "account_token.h"
#include <algorithm>
#include <cctype>
#include <cmath>
#include <nlohmann/json.hpp>
#include "account_protocol.h"

namespace kelpie::account {
namespace {
using json = nlohmann::json;
constexpr std::size_t kMaxRefreshToken = 4096;

// An unusable refresh token is dropped rather than failing a valid sign-in.
std::string RefreshToken(const json& token) {
  if (!token.contains("refresh_token") || !token["refresh_token"].is_string()) return {};
  auto value = token["refresh_token"].get<std::string>();
  const bool printable = std::all_of(value.begin(), value.end(),
      [](unsigned char c) { return c > 0x20 && c < 0x7f; });
  return printable && value.size() <= kMaxRefreshToken ? value : std::string();
}
}  // namespace

AccountToken ParseAccountToken(const std::string& body, const std::string& client) {
  const auto token = json::parse(body);
  const auto value = token.at("access_token").get<std::string>();
  const auto seconds = token.at("expires_in").get<double>();
  auto type = token.value("token_type", "");
  for (auto& c : type) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  const std::string scopes = " " + token.value("scope", std::string(kAccountScopes)) + " ";
  if (value.empty() || type != "bearer" || !std::isfinite(seconds) || seconds <= 0 || seconds > 2592000 ||
      scopes.find(" settings.read ") == std::string::npos || scopes.find(" settings.write ") == std::string::npos)
    throw AccountFailure(403);
  return {value, seconds, RefreshToken(token), client};
}

AccountToken RefreshAccountToken(const AccountRequest& request, const AccountSession& session) {
  AccountResponse response;
  try {
    response = request("/oauth/token", "POST", {}, json{{"grant_type", "refresh_token"},
        {"refresh_token", session.refresh_token}, {"client_id", session.client_id}}.dump(), {});
  } catch (const AccountFailure& failure) {
    if (failure.status == 400 || failure.status == 401 || failure.status == 403) throw AccountFailure(401);
    throw AccountFailure(0, kAccountUnreachable);
  } catch (...) {
    throw AccountFailure(0, kAccountUnreachable);
  }
  try {
    return ParseAccountToken(response.body, session.client_id);
  } catch (const AccountFailure&) {
    throw AccountFailure(401);  // A grant without the required scopes cannot be used.
  } catch (...) {
    throw AccountFailure(0, kAccountUnreachable);
  }
}

void RevokeAccountToken(const AccountRequest& request, const AccountSession& session) noexcept {
  try {
    request("/oauth/revoke", "POST", {}, json{{"token", session.refresh_token},
        {"client_id", session.client_id}}.dump(), {});
  } catch (...) {
  }
}
}  // namespace kelpie::account
