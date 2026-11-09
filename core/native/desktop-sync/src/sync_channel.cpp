#include "sync_channel.h"

#include "base64url.h"

namespace kelpie::desktop_sync {

SessionKeys DeriveSessionKeys(const Bytes& shared_secret, const Bytes& transcript_hash) {
  return {HkdfSha256(shared_secret, transcript_hash, "kelpie-sync-v1 i2r", 32),
          HkdfSha256(shared_secret, transcript_hash, "kelpie-sync-v1 r2i", 32)};
}

Bytes ChannelNonce(std::uint64_t seq) {
  Bytes nonce(kGcmNonceBytes, 0);
  for (int i = 0; i < 8; ++i) nonce[4 + i] = static_cast<std::uint8_t>(seq >> (56 - 8 * i));
  return nonce;
}

Bytes ChannelAad(const std::string& session_id, Direction direction, std::uint64_t seq) {
  std::string text = "kelpie-sync-v1";
  text.push_back('\0');
  text += session_id;
  text.push_back('\0');
  text += direction == Direction::kRequest ? "req" : "res";
  text.push_back('\0');
  text += std::to_string(seq);
  return ToBytes(text);
}

std::optional<std::string> SealBox(const SessionKeys& keys, Direction direction, const std::string& session_id,
                                   std::uint64_t seq, const std::string& plaintext) {
  const auto& key = direction == Direction::kRequest ? keys.i2r : keys.r2i;
  const auto box = AesGcmSeal(key, ChannelNonce(seq), ChannelAad(session_id, direction, seq), ToBytes(plaintext));
  if (!box) return std::nullopt;
  return sync::Base64UrlEncode(box->data(), box->size());
}

std::optional<std::string> OpenBox(const SessionKeys& keys, Direction direction, const std::string& session_id,
                                   std::uint64_t seq, const std::string& box) {
  const auto decoded = sync::Base64UrlDecode(box);
  if (!decoded) return std::nullopt;
  const auto& key = direction == Direction::kRequest ? keys.i2r : keys.r2i;
  const auto plain = AesGcmOpen(key, ChannelNonce(seq), ChannelAad(session_id, direction, seq), *decoded);
  if (!plain) return std::nullopt;
  return ToString(*plain);
}

bool ReplayWindow::Acceptable(std::uint64_t seq) const {
  if (seq == 0) return false;
  if (seq > highest_) return true;
  const std::uint64_t behind = highest_ - seq;
  if (behind == 0 || behind > kSize) return false;
  return (seen_ & (std::uint64_t{1} << (behind - 1))) == 0;
}

void ReplayWindow::Accept(std::uint64_t seq) {
  if (seq > highest_) {
    const std::uint64_t shift = seq - highest_;
    // The old highest becomes offset shift-1; anything older than the window falls out.
    seen_ = shift > kSize ? 0 : (shift == kSize ? 0 : seen_ << shift);
    if (highest_ != 0 && shift <= kSize) seen_ |= std::uint64_t{1} << (shift - 1);
    highest_ = seq;
    return;
  }
  const std::uint64_t behind = highest_ - seq;
  if (behind >= 1 && behind <= kSize) seen_ |= std::uint64_t{1} << (behind - 1);
}

}  // namespace kelpie::desktop_sync
