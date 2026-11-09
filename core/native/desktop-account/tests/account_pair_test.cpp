// Cookie sync's account calls: fenced identity, pairing ticket issue and
// validation over the authorized request path, against a fake UOA transport.
#include "account_service.h"
#include <cassert>
#include <chrono>
#include <thread>

using namespace kelpie::account;
using Json = nlohmann::json;
namespace {
// A fake UOA: tickets are a deterministic function of the subject, challenge
// and client id, and validation checks all three plus the bearer.
struct FakeUoa {
  std::string subject = "owner";
  int pair_failure = 0, validate_failure = 0;
  int pairs = 0, validations = 0;
  std::string last_token;
  static std::string Ticket(const std::string& subject, const std::string& challenge, const std::string& client) {
    return "t." + subject + "." + challenge + "." + client;
  }
  AccountResponse Request(const std::string& path, const std::string&, const std::string& token,
                          const std::string& body, const std::string&) {
    if (path == "/oauth/me") return {Json{{"sub", subject}, {"email", subject + "@example.org"}}.dump(), {}};
    if (path == kAccountBookmarks) return {R"({"value":[]})", {}};
    if (path == "/oauth/me/avatar") throw AccountFailure(404);
    if (path == "/oauth/revoke") return {"{}", {}};
    last_token = token;
    const auto request = Json::parse(body);
    if (path == "/oauth/kelpie/pair") {
      ++pairs;
      if (pair_failure) throw AccountFailure(pair_failure);
      assert(request.size() == 2);
      return {Json{{"pairing_ticket", Ticket(subject, request.at("challenge"), request.at("clientId"))},
                   {"expires_in", 120}}.dump(), {}};
    }
    assert(path == "/oauth/kelpie/pair/validate");
    ++validations;
    if (validate_failure) throw AccountFailure(validate_failure);
    const bool active = request.at("ticket") == Ticket(subject, request.at("challenge"), request.at("clientId"));
    return {active ? Json{{"active", true}, {"expires_at", 1}}.dump() : R"({"active":false})", {}};
  }
  AccountRequest Transport() {
    return [this](const auto& p, const auto& m, const auto& t, const auto& b, const auto& v) {
      return Request(p, m, t, b, v);
    };
  }
};

template <typename Body>
int Status(Body&& body) {
  try { body(); } catch (const AccountFailure& failure) { return failure.status; }
  return -1;
}

void IssueAndValidate() {
  kelpie::BookmarkStore local;
  FakeUoa uoa;
  AccountService account(local, uoa.Transport());
  const auto signed_out = account.CurrentIdentity();
  assert(!signed_out.signed_in && !signed_out.hosted && signed_out.subject.empty());
  assert(Status([&] { account.IssuePairTicket("c", "kelpie-sync:i:r"); }) == 401);
  assert(uoa.pairs == 0);

  account.CompleteSignIn({"access", 3600, {}, {}}, 0);
  const auto identity = account.CurrentIdentity();
  assert(identity.signed_in && identity.subject == "owner" && account.Subject() == "owner");
  assert(identity.generation != signed_out.generation && account.Generation() == identity.generation);

  const auto ticket = account.IssuePairTicket("challenge", "kelpie-sync:i:abc", identity.generation);
  assert(ticket == FakeUoa::Ticket("owner", "challenge", "kelpie-sync:i:abc"));
  assert(uoa.last_token == "access");
  assert(account.ValidatePairTicket(ticket, "challenge", "kelpie-sync:i:abc", identity.generation));
  // A reflected or retargeted proof is refused without touching the session.
  assert(!account.ValidatePairTicket(ticket, "challenge", "kelpie-sync:r:abc"));
  assert(!account.ValidatePairTicket(ticket, "other", "kelpie-sync:i:abc"));
  uoa.validate_failure = 403;
  assert(!account.ValidatePairTicket(ticket, "challenge", "kelpie-sync:i:abc"));
  uoa.validate_failure = 503;
  assert(Status([&] { account.ValidatePairTicket(ticket, "challenge", "kelpie-sync:i:abc"); }) == 503);
  uoa.validate_failure = 0;
  assert(account.State().signed_in);

  // A stale fence is refused before any UOA call and keeps the session.
  const int before = uoa.pairs;
  assert(Status([&] { account.IssuePairTicket("c", "k", identity.generation + 1); }) == 409);
  assert(uoa.pairs == before && account.State().signed_in);

  // UOA rejecting this device's own credential ends the session and moves the generation.
  uoa.pair_failure = 401;
  assert(Status([&] { account.IssuePairTicket("c", "k", identity.generation); }) == 401);
  const auto expired = account.CurrentIdentity();
  assert(!expired.signed_in && expired.subject.empty() && expired.generation != identity.generation);
  uoa.pair_failure = 0;

  // Sign-in, sign-out and account switch each produce a new generation.
  account.CompleteSignIn({"access", 3600, {}, {}}, 1);
  const auto again = account.CurrentIdentity();
  assert(again.signed_in && again.generation != expired.generation);
  account.SignOut();
  const auto out = account.CurrentIdentity();
  assert(!out.signed_in && out.generation != again.generation);
  uoa.subject = "second";
  account.CompleteSignIn({"access", 3600, {}, {}}, 2);
  const auto switched = account.CurrentIdentity();
  assert(switched.signed_in && switched.subject == "second" && switched.generation != out.generation);
  assert(account.IssuePairTicket("c", "k") == FakeUoa::Ticket("second", "c", "k"));
}

void EmbeddedSessionsNeverPair() {
  kelpie::BookmarkStore local;
  AccountService account(local);
  auto host = std::make_shared<HostSession>();
  host->state = [] { return HostSessionState{"person", "epoch-1"}; };
  host->request = [](const auto& path, const auto&, const auto&, const auto&) -> AccountResponse {
    if (path == "/oauth/me") return {R"({"sub":"person","email":"person@example.test"})", {}};
    if (path == "/oauth/me/avatar") throw AccountFailure(404);
    if (path == kAccountBookmarks) return {R"({"value":[]})", "v"};
    assert(false && "embedded sessions must not request pairing proofs");
    return {};
  };
  account.UseHostSession(host);
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
  while (!account.State().signed_in && std::chrono::steady_clock::now() < deadline) {
    account.Poll();
    std::this_thread::sleep_for(std::chrono::milliseconds(5));
  }
  const auto identity = account.CurrentIdentity();
  assert(identity.hosted && identity.signed_in);
  assert(Status([&] { account.IssuePairTicket("c", "k"); }) == 403);
  assert(Status([&] { account.ValidatePairTicket("t", "c", "k"); }) == 403);
}
}  // namespace

int main() {
  IssueAndValidate();
  EmbeddedSessionsNeverPair();
  return 0;
}
