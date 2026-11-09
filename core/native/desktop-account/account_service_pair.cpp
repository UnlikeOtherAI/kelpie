// Cookie sync's view of the account: a fenced identity and the two UOA
// pairing-proof calls. Proofs travel over the existing authorized request
// path, so the access token never leaves this service.
#include "account_service.h"

namespace kelpie::account {
namespace {
using json = nlohmann::json;
constexpr std::size_t kMaxTicketBytes = 8192;

// A caller fenced on an older identity. Not a UOA refusal: the session stays.
AccountFailure StaleIdentity() { return AccountFailure(409, "The UOA account changed during the request."); }
}  // namespace

AccountService::Identity AccountService::CurrentIdentity() const {
  std::lock_guard lock(mutex_);
  Identity identity;
  identity.hosted = host_session_ != nullptr;
  identity.signed_in = state_.signed_in && !subject_.empty();
  if (identity.signed_in) identity.subject = subject_;
  identity.generation = identity_generation_;
  return identity;
}

std::string AccountService::Subject() const { return CurrentIdentity().subject; }

std::uint64_t AccountService::Generation() const { return CurrentIdentity().generation; }

std::uint64_t AccountService::PairGeneration(std::optional<std::uint64_t> expected) const {
  std::lock_guard lock(mutex_);
  if (host_session_) throw AccountFailure(403, "Cookie sync is unavailable in an embedded browser.");
  if (!state_.signed_in || subject_.empty()) throw AccountFailure(401);
  if (expected && *expected != identity_generation_) throw StaleIdentity();
  return generation_;
}

void AccountService::CheckPairIdentity(std::optional<std::uint64_t> expected) const {
  std::lock_guard lock(mutex_);
  if (expected && *expected != identity_generation_) throw StaleIdentity();
}

std::string AccountService::IssuePairTicket(const std::string& challenge, const std::string& client_id,
    std::optional<std::uint64_t> expected) {
  const auto generation = PairGeneration(expected);
  try {
    const auto response = Authorized(generation, "/oauth/kelpie/pair", "POST",
        json{{"challenge", challenge}, {"clientId", client_id}}.dump());
    CheckGeneration(generation);
    CheckPairIdentity(expected);
    const auto value = json::parse(response.body);
    const auto ticket = value.find("pairing_ticket");
    if (ticket == value.end() || !ticket->is_string() || ticket->get<std::string>().empty() ||
        ticket->get<std::string>().size() > kMaxTicketBytes) throw AccountFailure(0);
    return ticket->get<std::string>();
  } catch (const AccountFailure& failure) {
    if (failure.status == 401) ExpireSession(generation, failure.what());
    throw;
  } catch (const json::exception&) {
    throw AccountFailure(0);
  }
}

bool AccountService::ValidatePairTicket(const std::string& ticket, const std::string& challenge,
    const std::string& client_id, std::optional<std::uint64_t> expected) {
  const auto generation = PairGeneration(expected);
  try {
    const auto response = Authorized(generation, "/oauth/kelpie/pair/validate", "POST",
        json{{"ticket", ticket}, {"challenge", challenge}, {"clientId", client_id}}.dump());
    CheckGeneration(generation);
    CheckPairIdentity(expected);
    const auto value = json::parse(response.body);
    const auto active = value.find("active");
    return active != value.end() && active->is_boolean() && active->get<bool>();
  } catch (const AccountFailure& failure) {
    // 401 rejects this device's own credential and ends its session. Other
    // client errors refuse the peer's proof; transient failures propagate.
    if (failure.status == 401) { ExpireSession(generation, failure.what()); throw; }
    if (failure.status >= 400 && failure.status < 500 && failure.status != 408 && failure.status != 409 &&
        failure.status != 429) return false;
    throw;
  } catch (const json::exception&) {
    throw AccountFailure(0);
  }
}
}  // namespace kelpie::account
