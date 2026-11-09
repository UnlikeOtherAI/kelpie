#pragma once

// Cookie sync channel crypto for Windows (CNG) and Linux (OpenSSL libcrypto):
// P-256 ECDH, HMAC/HKDF-SHA256 and AES-256-GCM. Both backends must reproduce
// core/native/core-sync/tests/vectors/handshake-v1.json exactly.

#include <cstddef>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace kelpie::desktop_sync {

using Bytes = std::vector<std::uint8_t>;

inline constexpr std::size_t kPublicKeyBytes = 65;  // x9.63 uncompressed: 0x04 || X || Y
inline constexpr std::size_t kScalarBytes = 32;
inline constexpr std::size_t kGcmNonceBytes = 12;
inline constexpr std::size_t kGcmTagBytes = 16;

// Fills `size` bytes from the system CSPRNG. Throws std::runtime_error on failure.
Bytes RandomBytes(std::size_t size);

// One ephemeral P-256 key pair. Only the public key ever leaves it.
class EcdhKey {
 public:
  ~EcdhKey();
  EcdhKey(const EcdhKey&) = delete;
  EcdhKey& operator=(const EcdhKey&) = delete;

  // A fresh key pair. Throws std::runtime_error when the backend fails.
  static std::unique_ptr<EcdhKey> Generate();
  // Known key material (test vectors). Returns nullptr when it is invalid.
  static std::unique_ptr<EcdhKey> FromPrivate(const Bytes& scalar, const Bytes& public_key);

  const Bytes& PublicKey() const { return public_key_; }
  // The 32-byte X coordinate of the shared point, or nullopt when the peer key
  // is not a valid uncompressed point on P-256.
  std::optional<Bytes> SharedSecret(const Bytes& peer_public_key) const;

  struct Impl;

 private:
  EcdhKey();
  std::unique_ptr<Impl> impl_;
  Bytes public_key_;
};

// True only for a valid uncompressed point on P-256.
bool IsValidPublicKey(const Bytes& public_key);

Bytes HmacSha256(const Bytes& key, const Bytes& data);
// RFC 5869 extract-then-expand.
Bytes HkdfSha256(const Bytes& ikm, const Bytes& salt, std::string_view info, std::size_t length);

// ciphertext || 16-byte tag. Keys are 32 bytes, nonces 12 bytes.
std::optional<Bytes> AesGcmSeal(const Bytes& key, const Bytes& nonce, const Bytes& aad, const Bytes& plaintext);
// nullopt when the box does not authenticate.
std::optional<Bytes> AesGcmOpen(const Bytes& key, const Bytes& nonce, const Bytes& aad, const Bytes& box);

inline Bytes ToBytes(std::string_view text) { return Bytes(text.begin(), text.end()); }
inline std::string ToString(const Bytes& bytes) { return std::string(bytes.begin(), bytes.end()); }

}  // namespace kelpie::desktop_sync
