#include "account_session_store.h"
#include <nlohmann/json.hpp>

namespace kelpie::account {
namespace {
constexpr std::size_t kMaxField = 4096;

std::optional<std::string> Field(const nlohmann::json& value, const char* key) {
  if (!value.contains(key) || !value[key].is_string()) return std::nullopt;
  auto text = value[key].get<std::string>();
  if (text.empty() || text.size() > kMaxField) return std::nullopt;
  return text;
}
}  // namespace

std::string EncodeAccountSession(const AccountSession& session) {
  return nlohmann::json{{"client_id", session.client_id}, {"refresh_token", session.refresh_token}}.dump();
}

std::optional<AccountSession> DecodeAccountSession(const std::string& text) {
  const auto value = nlohmann::json::parse(text, nullptr, false);
  if (!value.is_object()) return std::nullopt;
  auto client = Field(value, "client_id");
  auto refresh = Field(value, "refresh_token");
  if (!client || !refresh) return std::nullopt;
  return AccountSession{std::move(*client), std::move(*refresh)};
}
}  // namespace kelpie::account
