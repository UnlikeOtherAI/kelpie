#include "kelpie/peer_approval.h"
#include <chrono>
#include <unordered_set>

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
void PeerApprovalQueue::SetAvailable(bool available) { std::lock_guard lock(mutex_); available_ = available; }
bool PeerApprovalQueue::IsTrusted(const std::string& source) const { return store_.IsTrusted(source); }

void PeerApprovalQueue::Collect() {
  const auto now = clock_();
  for (auto it = requests_.begin(); it != requests_.end();) {
    if (it->second.at("expiresAt").get<std::int64_t>() <= now) it = requests_.erase(it); else ++it;
  }
  for (auto it = denied_.begin(); it != denied_.end();) {
    if (it->second <= now) it = denied_.erase(it); else ++it;
  }
}

PeerApprovalQueue::Response PeerApprovalQueue::Start(const std::string& source, const Json& body) {
  const auto address = CanonicalPeerAddress(source);
  if (!address) return Error(403, "FORBIDDEN", "A numeric socket peer is required");
  if (!body.is_object()) return Error(400, "INVALID_JSON", "Expected a JSON object");
  if (body.contains("account")) return Error(409, "ACCOUNT_PAIRING_UNAVAILABLE", "Use explicit computer pairing on this platform");
  if (!body.contains("clientId") || !body["clientId"].is_string() || body["clientId"].get<std::string>().empty() ||
      body["clientId"].get<std::string>().size() > 200)
    return Error(400, "MISSING_PARAM", "clientId is required");
  if (body.contains("clientName") && !body["clientName"].is_string())
    return Error(400, "INVALID_PARAMS", "clientName must be a string");
  std::lock_guard lock(mutex_);
  Collect();
  const bool trusted = store_.IsTrusted(*address);
  if (!trusted && !available_) return Error(409, "APPROVAL_UNAVAILABLE", "Open Kelpie with its native UI to approve this computer");
  if (!trusted && denied_.count(*address)) return Error(403, "DENIED", "Requests from this computer are temporarily suppressed");
  std::unordered_set<std::string> sources;
  std::size_t from_source = 0;
  for (const auto& [key, request] : requests_) {
    const std::string peer = request.at("sourceAddress");
    sources.insert(peer);
    if (peer == *address) ++from_source;
  }
  if (from_source >= 32 || (!sources.count(*address) && sources.size() >= 8))
    return Error(429, "RATE_LIMITED", "Too many pending pairing requests");
  const auto id = PeerRequestNonce();
  const auto label = SanitizePeerLabel(body.value("clientName", std::string()));
  requests_[id] = {{"requestId", id}, {"sourceAddress", *address}, {"clientName", label},
      {"createdAt", clock_()}, {"expiresAt", clock_() + 300000}, {"approved", trusted}, {"token", PeerRequestNonce()}};
  return {202, {{"status", "pending"}, {"requestId", id}, {"sourceAddress", *address},
      {"expiresAt", requests_[id]["expiresAt"]}, {"approvalRequired", !trusted}}};
}

PeerApprovalQueue::Json PeerApprovalQueue::Status(const std::string& source, const std::string& request_id) {
  const auto address = CanonicalPeerAddress(source);
  std::lock_guard lock(mutex_);
  Collect();
  const auto it = requests_.find(request_id);
  if (!address || it == requests_.end() || it->second["sourceAddress"] != *address) return {{"status", "not_found"}};
  if (it->second.value("denied", false)) return {{"status", "denied"}};
  if (!it->second.at("approved").get<bool>()) return {{"status", "pending"}};
  if (!store_.IsTrusted(*address)) { requests_.erase(it); return {{"status", "denied"}}; }
  Json result = {{"status", "approved"}, {"scope", "persistent"}, {"token", it->second["token"]}};
  requests_.erase(it);
  return result;
}

PeerApprovalQueue::Json PeerApprovalQueue::Pending() {
  std::lock_guard lock(mutex_);
  Collect();
  Json result;
  std::unordered_map<std::string, bool> trusted;
  for (auto& [id, request] : requests_) {
    const std::string source = request.at("sourceAddress");
    if (!trusted.count(source)) trusted[source] = store_.IsTrusted(source);
    if (!request.value("denied", false) && trusted[source]) request["approved"] = true;
    if (request.at("approved").get<bool>() || request.value("denied", false)) continue;
    if (result.is_null() || request["createdAt"] < result["createdAt"]) result = request;
  }
  if (result.is_object()) result.erase("token");
  return result;
}

bool PeerApprovalQueue::Approve(const std::string& id) {
  std::lock_guard lock(mutex_);
  Collect();
  const auto it = requests_.find(id);
  if (it == requests_.end() || it->second.value("denied", false)) return false;
  const std::string address = it->second["sourceAddress"];
  try { store_.Approve(address, it->second["clientName"]); } catch (...) { return false; }
  for (auto& [key, request] : requests_) if (request["sourceAddress"] == address) request["approved"] = true;
  return true;
}

void PeerApprovalQueue::Deny(const std::string& id) {
  std::lock_guard lock(mutex_);
  Collect();
  const auto it = requests_.find(id);
  if (it == requests_.end()) return;
  const std::string address = it->second["sourceAddress"];
  denied_[address] = clock_() + 600000;
  for (auto& [key, request] : requests_) if (request["sourceAddress"] == address) request["denied"] = true;
}
}  // namespace kelpie
