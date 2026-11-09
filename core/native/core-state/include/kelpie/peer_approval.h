#pragma once

#include <mutex>
#include <functional>
#include <unordered_map>
#include "kelpie/peer_trust.h"

namespace kelpie {

// HTTP workers stage challenges; the native owner loop presents one dialog per proven computer key.
class PeerApprovalQueue {
 public:
  using Json = nlohmann::json;
  struct Response { int status; Json body; };
  explicit PeerApprovalQueue(std::filesystem::path path = PeerTrustStore::DefaultPath(),
                             std::function<std::int64_t()> clock = {});
  void SetAvailable(bool available);
  Response Start(const std::string& source, const Json& body);
  Json Status(const std::string& source, const std::string& request_id);
  Json Pending();
  bool Approve(const std::string& request_id);
  void Deny(const std::string& request_id);
  std::optional<std::string> Authorize(const std::string& source, const std::string& token) const;
  PeerTrustStore& store() { return store_; }

 private:
  void Collect();
  PeerTrustStore store_;
  std::function<std::int64_t()> clock_;
  std::mutex mutex_;
  bool available_ = false;
  std::string presented_request_id_;
  std::unordered_map<std::string, Json> requests_;
  std::unordered_map<std::string, std::int64_t> denied_;
};
}  // namespace kelpie
