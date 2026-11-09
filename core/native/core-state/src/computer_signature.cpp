#include "kelpie/peer_trust.h"

// Use standard integer types in this C++ consumer. The upstream pre-C99
// MSVC fallback otherwise redeclares uint32_t as unsigned long.
#include <stdint.h>
#define FIXEDINT_H_INCLUDED
extern "C" {
#include "ed25519.h"
#include "ge.h"
#include "sc.h"
#include "sha512.h"
}
#include <algorithm>
#include <array>

namespace kelpie {
namespace {
int Digit(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  return -1;
}
template <std::size_t N> bool Decode(const std::string& text, std::array<unsigned char, N>& bytes) {
  if (text.size() != N * 2) return false;
  for (std::size_t i = 0; i < N; ++i) {
    const auto high = Digit(text[i * 2]), low = Digit(text[i * 2 + 1]);
    if (high < 0 || low < 0) return false;
    bytes[i] = static_cast<unsigned char>(high * 16 + low);
  }
  return true;
}

bool ValidPublicKey(const std::array<unsigned char, 32>& bytes) {
  ge_p3 point;
  if (ge_frombytes_negate_vartime(&point, bytes.data()) != 0) return false;
  std::array<unsigned char, 32> canonical{};
  ge_p3_tobytes(canonical.data(), &point);
  // The parser negates X; the encoded Y must still be canonical.
  for (std::size_t i = 0; i < 32; ++i) {
    const unsigned char mask = i == 31 ? 0x7f : 0xff;
    if ((canonical[i] & mask) != (bytes[i] & mask)) return false;
  }
  // Reject small-order keys: multiplying by Ed25519's cofactor must not
  // produce the identity. Such a key cannot prove a unique private identity.
  ge_p2 doubled;
  ge_p3_to_p2(&doubled, &point);
  for (int i = 0; i < 3; ++i) {
    ge_p1p1 next;
    ge_p2_dbl(&next, &doubled);
    ge_p1p1_to_p2(&doubled, &next);
  }
  ge_tobytes(canonical.data(), &doubled);
  return canonical[0] != 1 || std::any_of(canonical.begin() + 1, canonical.end(), [](unsigned char byte) { return byte != 0; });
}
}

bool IsComputerKey(const std::string& key) {
  std::array<unsigned char, 32> bytes{};
  return Decode(key, bytes) && ValidPublicKey(bytes);
}

std::string ComputerPairingMessage(const std::string& challenge, const std::string& key) {
  return "kelpie-computer-pair-v1\n" + challenge + "\n" + key;
}

bool VerifyComputerSignature(const std::string& key, const std::string& challenge, const std::string& signature) {
  std::array<unsigned char, 32> public_key{};
  std::array<unsigned char, 64> signed_bytes{};
  if (!Decode(key, public_key) || !ValidPublicKey(public_key) || !Decode(signature, signed_bytes)) return false;
  std::array<unsigned char, 64> scalar{};
  std::copy(signed_bytes.begin() + 32, signed_bytes.end(), scalar.begin());
  sc_reduce(scalar.data());
  if (!std::equal(scalar.begin(), scalar.begin() + 32, signed_bytes.begin() + 32)) return false;
  const auto message = ComputerPairingMessage(challenge, key);
  return ed25519_verify(signed_bytes.data(), reinterpret_cast<const unsigned char*>(message.data()),
      message.size(), public_key.data()) == 1;
}

std::string ComputerTokenHash(const std::string& token) {
  unsigned char bytes[64]{};
  sha512(reinterpret_cast<const unsigned char*>(token.data()), token.size(), bytes);
  constexpr char hex[] = "0123456789abcdef";
  std::string result;
  for (const auto byte : bytes) { result += hex[byte >> 4]; result += hex[byte & 15]; }
  return result;
}
}  // namespace kelpie
