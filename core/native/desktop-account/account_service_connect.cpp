#include "account_service.h"

namespace kelpie::account {
std::string AccountService::ConnectionOwner() const {
  std::lock_guard lock(mutex_);
  return state_.signed_in && !subject_.empty() ? std::string(kAccountOrigin)+"/"+subject_ : std::string();
}
nlohmann::json AccountService::ConnectionTicket() {
  std::uint64_t generation;
  { std::lock_guard lock(mutex_); if (!state_.signed_in) throw AccountFailure(401); generation=generation_; }
  try {
    const auto response=Authorized(generation,"/oauth/kelpie/connect","POST",
        R"({"resource":"https://api.nessie.works/api/kelpie/connect"})");
    CheckGeneration(generation);
    const auto value=nlohmann::json::parse(response.body);
    if (value.at("token_type")!="Bearer" || value.at("gateway_url")!="wss://api.nessie.works/api/kelpie/connect" ||
        !value.at("connection_ticket").is_string() || value.at("connection_ticket").get<std::string>().empty() ||
        !value.at("expires_in").is_number() || value.at("expires_in").get<double>()<=0 ||
        value.at("expires_in").get<double>()>120) throw AccountFailure(0);
    return value;
  } catch (const AccountFailure& failure) {
    if (failure.status==401) ExpireSession(generation,failure.what());
    // 403 needs new hosted consent, without silently widening a stored grant.
    throw;
  }
}
}
