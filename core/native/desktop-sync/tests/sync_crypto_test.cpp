// The platform crypto backend (CNG on Windows, OpenSSL elsewhere) reproduces
// every value in core-sync's shared handshake vectors.
#include <cassert>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <string>

#include <nlohmann/json.hpp>

#include "base64url.h"
#include "sync_channel.h"
#include "sync_crypto.h"
#include "sync_protocol.h"

using namespace kelpie::desktop_sync;
using nlohmann::json;

namespace {

Bytes Decode(const json& value) {
  const auto decoded = kelpie::sync::Base64UrlDecode(value.get<std::string>());
  assert(decoded);
  return *decoded;
}

std::string Encode(const Bytes& bytes) { return kelpie::sync::Base64UrlEncode(bytes.data(), bytes.size()); }

Bytes Hex(const std::string& text) {
  Bytes out;
  for (std::size_t i = 0; i + 1 < text.size(); i += 2) out.push_back(static_cast<std::uint8_t>(std::stoi(text.substr(i, 2), nullptr, 16)));
  return out;
}

void Vectors() {
  std::ifstream input(std::filesystem::path(KELPIE_SYNC_VECTORS));
  assert(input);
  const json v = json::parse(input);
  const auto initiator = EcdhKey::FromPrivate(Decode(v["initiator"]["privateKey"]), Decode(v["initiator"]["key"]));
  const auto responder = EcdhKey::FromPrivate(Decode(v["responder"]["privateKey"]), Decode(v["responder"]["key"]));
  assert(initiator && responder);

  const std::string challenge =
      Challenge({v["initiator"]["replica"], v["initiator"]["key"], v["initiator"]["nonce"]},
                {v["responder"]["replica"], v["responder"]["key"], v["responder"]["nonce"]});
  assert(challenge == v["challenge"].get<std::string>());

  const auto z1 = initiator->SharedSecret(Decode(v["responder"]["key"]));
  const auto z2 = responder->SharedSecret(Decode(v["initiator"]["key"]));
  assert(z1 && z2 && *z1 == *z2);
  assert(Encode(*z1) == v["sharedSecret"].get<std::string>());

  const SessionKeys keys = DeriveSessionKeys(*z1, Decode(v["challenge"]));
  assert(Encode(keys.i2r) == v["i2r"].get<std::string>());
  assert(Encode(keys.r2i) == v["r2i"].get<std::string>());
  const auto derived = DeriveKeys(*responder, v["initiator"]["key"], challenge);
  assert(derived && derived->i2r == keys.i2r && derived->r2i == keys.r2i);

  const std::string session = v["sessionId"];
  for (const auto& message : v["messages"]) {
    const std::uint64_t seq = message["seq"];
    const Direction direction = message["direction"] == "req" ? Direction::kRequest : Direction::kResponse;
    assert(Encode(ChannelNonce(seq)) == message["nonce"].get<std::string>());
    assert(Encode(ChannelAad(session, direction, seq)) == message["aad"].get<std::string>());
    const auto box = SealBox(keys, direction, session, seq, message["plaintext"]);
    assert(box && *box == message["box"].get<std::string>());
    const auto plain = OpenBox(keys, direction, session, seq, message["box"]);
    assert(plain && *plain == message["plaintext"].get<std::string>());
    // Every bound value matters: the other direction, another seq or session, a flipped bit.
    const Direction other = direction == Direction::kRequest ? Direction::kResponse : Direction::kRequest;
    assert(!OpenBox(keys, other, session, seq, message["box"]));
    assert(!OpenBox(keys, direction, session, seq + 1, message["box"]));
    assert(!OpenBox(keys, direction, session + "x", seq, message["box"]));
    Bytes tampered = Decode(message["box"]);
    tampered.back() ^= 1;
    assert(!OpenBox(keys, direction, session, seq, Encode(tampered)));
  }
}

void Points() {
  const auto key = EcdhKey::Generate();
  assert(key->PublicKey().size() == kPublicKeyBytes && key->PublicKey()[0] == 0x04);
  assert(IsValidPublicKey(key->PublicKey()));
  const auto other = EcdhKey::Generate();
  const auto a = key->SharedSecret(other->PublicKey());
  const auto b = other->SharedSecret(key->PublicKey());
  assert(a && b && *a == *b && a->size() == 32);
  // Off-curve, compressed and truncated points never become keys.
  Bytes off_curve(65, 0x11);
  off_curve[0] = 0x04;
  assert(!IsValidPublicKey(off_curve));
  assert(!key->SharedSecret(off_curve));
  Bytes compressed(key->PublicKey().begin(), key->PublicKey().begin() + 33);
  compressed[0] = 0x02;
  assert(!IsValidPublicKey(compressed));
  Bytes zero(65, 0);
  zero[0] = 0x04;
  assert(!IsValidPublicKey(zero));
  assert(RandomBytes(32) != RandomBytes(32));
}

void Rfc5869() {
  // RFC 5869 test case 1.
  const Bytes okm = HkdfSha256(Bytes(22, 0x0b), Hex("000102030405060708090a0b0c"),
                               std::string("\xf0\xf1\xf2\xf3\xf4\xf5\xf6\xf7\xf8\xf9", 10), 42);
  assert(okm == Hex("3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"));
}

}  // namespace

int main() {
  Vectors();
  Points();
  Rfc5869();
  std::puts("sync_crypto_test passed");
  return 0;
}
