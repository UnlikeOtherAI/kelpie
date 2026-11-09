#pragma once

// The encrypted exchange channel: session keys, nonces, AAD, boxes and the
// responder's replay window. See "Handshake and channel" in
// docs/plans/2026-11-09-p2p-cookie-sync.md.

#include <cstdint>
#include <optional>
#include <string>

#include "sync_crypto.h"

namespace kelpie::desktop_sync {

struct SessionKeys {
  Bytes i2r;  // seals requests (initiator → responder)
  Bytes r2i;  // seals responses
};

enum class Direction { kRequest, kResponse };

// i2r/r2i = HKDF-SHA256(ikm = ECDH secret, salt = transcript hash T).
SessionKeys DeriveSessionKeys(const Bytes& shared_secret, const Bytes& transcript_hash);

// 4 zero bytes || 64-bit big-endian seq.
Bytes ChannelNonce(std::uint64_t seq);
// "kelpie-sync-v1\0<sessionId>\0<req|res>\0<seq in decimal>".
Bytes ChannelAad(const std::string& session_id, Direction direction, std::uint64_t seq);

// base64url(ciphertext || tag), or nullopt when the backend fails.
std::optional<std::string> SealBox(const SessionKeys& keys, Direction direction, const std::string& session_id,
                                   std::uint64_t seq, const std::string& plaintext);
// The plaintext, or nullopt when the box is malformed or does not authenticate.
std::optional<std::string> OpenBox(const SessionKeys& keys, Direction direction, const std::string& session_id,
                                   std::uint64_t seq, const std::string& box);

// Accepts a seq it has not seen that is no more than 64 below the highest
// seen. Not thread-safe; the session guards it.
class ReplayWindow {
 public:
  static constexpr std::uint64_t kSize = 64;
  bool Acceptable(std::uint64_t seq) const;
  // Records an authenticated seq. Call only after Acceptable() and a
  // successful open, so a forged box cannot burn a sequence number.
  void Accept(std::uint64_t seq);

 private:
  std::uint64_t highest_ = 0;
  std::uint64_t seen_ = 0;  // bit i: highest_ - 1 - i was seen
};

}  // namespace kelpie::desktop_sync
