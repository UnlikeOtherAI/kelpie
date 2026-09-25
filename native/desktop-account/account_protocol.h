#pragma once
#include <string>
#include <nlohmann/json.hpp>
#include "account_transport.h"

namespace kelpie::account {
inline constexpr char kAccountOrigin[] = "https://authentication.unlikeotherai.com";
inline constexpr char kAccountScopes[] = "openid profile settings.read settings.write";
inline constexpr char kAccountBookmarks[] = "/oauth/me/settings/browser/bookmarks";
std::string RandomAccountValue();
std::string AccountChallenge(const std::string& verifier);
std::string AccountAuthorizationUrl(const std::string& client, const std::string& redirect,
                                  const std::string& state, const std::string& verifier);
bool SameAccountState(const std::string& a, const std::string& b);
std::string AccountBookmarkID(const nlohmann::json& item);
nlohmann::json VisibleAccountBookmarks(const nlohmann::json& raw);
nlohmann::json MutateAccountBookmarks(nlohmann::json raw, const std::string& action,
                                     const nlohmann::json& params);
}  // namespace kelpie::account
