#pragma once

#include <filesystem>
#include <optional>
#include <string>
#include <nlohmann/json.hpp>

namespace kelpie {

// Socket addresses are display/routing data, never durable computer identity.
std::optional<std::string> CanonicalPeerAddress(const std::string& address);
bool IsLoopbackPeer(const std::string& address);
bool IsSafeControlHost(const std::string& host);
std::string PeerRequestNonce();
std::string SanitizePeerLabel(const std::string& name);

bool IsComputerKey(const std::string& key);
std::string ComputerPairingMessage(const std::string& challenge, const std::string& key);
bool VerifyComputerSignature(const std::string& key, const std::string& challenge, const std::string& signature);
std::string ComputerTokenHash(const std::string& token);

class PeerTrustStore {
 public:
  explicit PeerTrustStore(std::filesystem::path path = DefaultPath());
  static std::filesystem::path DefaultPath();
  bool IsTrusted(const std::string& public_key) const;
  // Throws on unavailable/corrupt storage. Never claims a failed write succeeded.
  nlohmann::json List() const;
  void Approve(const std::string& public_key, const std::string& name, const std::string& address);
  void IssueToken(const std::string& public_key, const std::string& token, const std::string& address);
  std::optional<std::string> Authorize(const std::string& token) const;
  void Revoke(const std::string& public_key);

 private:
  std::filesystem::path path_;
};

}  // namespace kelpie
