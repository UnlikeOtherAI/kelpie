#pragma once

#include <filesystem>
#include <optional>
#include <string>
#include <nlohmann/json.hpp>

namespace kelpie {

// Only socket-derived numeric addresses belong here. No DNS or forwarded headers.
std::optional<std::string> CanonicalPeerAddress(const std::string& address);
bool IsLoopbackPeer(const std::string& address);
bool IsSafeControlHost(const std::string& host);
std::string PeerRequestNonce();
std::string SanitizePeerLabel(const std::string& name);

class PeerTrustStore {
 public:
  explicit PeerTrustStore(std::filesystem::path path = DefaultPath());
  static std::filesystem::path DefaultPath();
  bool IsTrusted(const std::string& address) const;
  // Throws on unavailable/corrupt storage. Never claims a failed write succeeded.
  nlohmann::json List() const;
  void Approve(const std::string& address, const std::string& name);
  void Revoke(const std::string& address);

 private:
  std::filesystem::path path_;
};

}  // namespace kelpie
