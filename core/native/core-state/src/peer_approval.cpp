#include "kelpie/peer_approval.h"
#include <chrono>

namespace kelpie {
namespace {
std::int64_t Now() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count();
}
PeerApprovalQueue::Response Error(int status, const char* code, const char* message) {
  return {status, {{"success", false}, {"error", {{"code", code}, {"message", message}}}}};
}
}
PeerApprovalQueue::PeerApprovalQueue(std::filesystem::path path, std::function<std::int64_t()> clock)
    : store_(std::move(path)), clock_(clock ? std::move(clock) : Now) {}
void PeerApprovalQueue::SetAvailable(bool available) {
  std::lock_guard lock(mutex_); available_ = available;
  if (!available) presented_request_id_.clear();
}
std::optional<std::string> PeerApprovalQueue::Authorize(const std::string& source, const std::string& token) const {
  if (IsLoopbackPeer(source)) return "localhost";
  return store_.Authorize(token);
}
void PeerApprovalQueue::Collect() {
  const auto now = clock_();
  for (auto it = requests_.begin(); it != requests_.end();) {
    // The signature challenge expires; a verified computer already shown to a
    // person stays answerable until their decision, including behind OS dialogs.
    if (it->second.at("expiresAt").get<std::int64_t>() <= now && it->first != presented_request_id_)
      it = requests_.erase(it); else ++it;
  }
  for (auto it = denied_.begin(); it != denied_.end();) {
    if (it->second <= now) it = denied_.erase(it); else ++it;
  }
}
PeerApprovalQueue::Response PeerApprovalQueue::Start(const std::string& source, const Json& body) {
  const auto address = CanonicalPeerAddress(source);
  if (!address) return Error(403, "FORBIDDEN", "A numeric socket peer is required");
  if (!body.is_object()) return Error(400, "INVALID_JSON", "Expected a JSON object");
  if (body.contains("account")) return Error(409, "ACCOUNT_PAIRING_UNAVAILABLE", "Use computer pairing on this platform");
  for (const auto* field : {"computerPublicKey", "requestId", "computerSignature"}) {
    if (body.contains(field) && !body[field].is_string()) return Error(400, "INVALID_PARAMS", "Computer proof fields must be strings");
  }
  const auto key = body.value("computerPublicKey", std::string());
  if (!IsComputerKey(key)) return Error(400, "COMPUTER_KEY_REQUIRED", "Update the Kelpie CLI to pair this computer");
  if (!body.contains("clientId") || !body["clientId"].is_string() || body["clientId"].get<std::string>().empty() ||
      body["clientId"].get<std::string>().size() > 200)
    return Error(400, "MISSING_PARAM", "clientId is required");
  if (body.contains("clientName") && !body["clientName"].is_string())
    return Error(400, "INVALID_PARAMS", "clientName must be a string");
  std::lock_guard lock(mutex_);
  Collect();
  if (body.contains("requestId")) {
    const auto id = body.value("requestId", std::string());
    const auto it = requests_.find(id);
    if (it == requests_.end() || it->second["publicKey"] != key || it->second["sourceAddress"] != *address ||
        it->second.value("verified", false) ||
        !VerifyComputerSignature(key, id, body.value("computerSignature", std::string())))
      return Error(403, "COMPUTER_AUTH_FAILED", "Computer signature verification failed");
    auto& request = it->second;
    request["verified"] = true;
    const bool trusted = store_.IsTrusted(key);
    if (!trusted && !available_) { requests_.erase(it); return Error(409, "APPROVAL_UNAVAILABLE", "Open Kelpie to approve this computer"); }
    if (denied_.count(key)) return Error(403, "DENIED", "Requests from this computer are temporarily suppressed");
    request["approved"] = trusted;
    return {202, {{"status", "pending"}, {"requestId", id}, {"sourceAddress", *address},
        {"expiresAt", request["expiresAt"]}, {"approvalRequired", !trusted}}};
  }
  if (denied_.count(key)) return Error(403, "DENIED", "Requests from this computer are temporarily suppressed");
  std::size_t from_source = 0;
  for (const auto& [id, request] : requests_) if (request["sourceAddress"] == *address) ++from_source;
  if (from_source >= 32 || requests_.size() >= 256) return Error(429, "RATE_LIMITED", "Too many pairing requests");
  const auto id = PeerRequestNonce();
  requests_[id] = {{"requestId", id}, {"sourceAddress", *address}, {"publicKey", key},
      {"clientName", SanitizePeerLabel(body.value("clientName", std::string()))},
      {"createdAt", clock_()}, {"expiresAt", clock_() + 300000}, {"verified", false}, {"approved", false}};
  return {202, {{"status", "computer_challenge"}, {"requestId", id}, {"sourceAddress", *address},
      {"expiresAt", requests_[id]["expiresAt"]}, {"approvalRequired", false}}};
}
PeerApprovalQueue::Json PeerApprovalQueue::Status(const std::string& source, const std::string& request_id) {
  const auto address = CanonicalPeerAddress(source);
  std::lock_guard lock(mutex_);
  Collect();
  const auto it = requests_.find(request_id);
  if (!address || it == requests_.end() || it->second["sourceAddress"] != *address) return {{"status", "not_found"}};
  auto& request = it->second;
  if (!request.value("verified", false)) return {{"status", "not_found"}};
  if (request.value("denied", false)) return {{"status", "denied"}};
  if (!request.at("approved").get<bool>()) return {{"status", "pending"}};
  const std::string key = request["publicKey"];
  if (!store_.IsTrusted(key)) { requests_.erase(it); return {{"status", "denied"}}; }
  const auto token = PeerRequestNonce();
  store_.IssueToken(key, token, *address);
  requests_.erase(it);
  return {{"status", "approved"}, {"scope", "persistent"}, {"token", token}};
}
PeerApprovalQueue::Json PeerApprovalQueue::Pending() {
  std::lock_guard lock(mutex_);
  Collect();
  Json result;
  for (auto& [id, request] : requests_) {
    if (!request.value("verified", false) || request.value("denied", false)) continue;
    if (store_.IsTrusted(request["publicKey"])) request["approved"] = true;
    if (request.at("approved").get<bool>()) continue;
    if (result.is_null() || request["createdAt"] < result["createdAt"]) result = request;
  }
  presented_request_id_ = result.is_null() ? std::string() : result.at("requestId").get<std::string>();
  return result;
}
bool PeerApprovalQueue::Approve(const std::string& id) {
  std::lock_guard lock(mutex_);
  Collect();
  const auto it = requests_.find(id);
  if (it == requests_.end() || !it->second.value("verified", false) || it->second.value("denied", false)) return false;
  const std::string key = it->second["publicKey"];
  try { store_.Approve(key, it->second["clientName"], it->second["sourceAddress"]); } catch (...) { return false; }
  for (auto& [request_id, request] : requests_) if (request["publicKey"] == key && request.value("verified", false)) {
    request["approved"] = true;
    request["expiresAt"] = clock_() + 300000;
  }
  presented_request_id_.clear();
  return true;
}
void PeerApprovalQueue::Deny(const std::string& id) {
  std::lock_guard lock(mutex_);
  Collect();
  const auto it = requests_.find(id);
  if (it == requests_.end()) return;
  const std::string key = it->second["publicKey"];
  denied_[key] = clock_() + 600000;
  for (auto& [request_id, request] : requests_) if (request["publicKey"] == key) {
    request["denied"] = true;
    request["expiresAt"] = clock_() + 300000;
  }
  presented_request_id_.clear();
}
}  // namespace kelpie
