#pragma once
#include "kelpie/peer_approval.h"
extern "C" {
#include "ed25519.h"
}
#include <cassert>
using Json = nlohmann::json;
struct Identity {
  unsigned char public_key[32]{}, private_key[64]{};
  std::string key;
  explicit Identity(unsigned char discriminator) {
    unsigned char seed[32]{}; seed[0] = discriminator;
    ed25519_create_keypair(public_key, private_key, seed);
    constexpr char hex[] = "0123456789abcdef";
    for (auto byte : public_key) { key += hex[byte >> 4]; key += hex[byte & 15]; }
  }
  std::string Sign(const std::string& challenge) const {
    const auto message = kelpie::ComputerPairingMessage(challenge, key);
    unsigned char signature[64]{};
    ed25519_sign(signature, reinterpret_cast<const unsigned char*>(message.data()), message.size(), public_key, private_key);
    constexpr char hex[] = "0123456789abcdef";
    std::string result;
    for (auto byte : signature) { result += hex[byte >> 4]; result += hex[byte & 15]; }
    return result;
  }
  Json Body(const std::string& client = "test") const {
    return {{"clientId", client}, {"clientName", "Test computer"}, {"computerPublicKey", key}};
  }
  std::string Start(kelpie::PeerApprovalQueue& queue, const std::string& ip, const std::string& client = "test") const {
    auto body = Body(client);
    const auto initial = queue.Start(ip, body);
    assert(initial.status == 202 && initial.body["status"] == "computer_challenge");
    const auto id = initial.body["requestId"].get<std::string>();
    body["requestId"] = id; body["computerSignature"] = Sign(id);
    assert(queue.Start(ip, body).status == 202);
    return id;
  }
};
