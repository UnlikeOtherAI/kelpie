#include "kelpie/state_c_api.h"
#include "kelpie/peer_trust.h"

#include <cstring>
#include <new>

extern "C" char* kelpie_peer_trust_request(const char* path, const char* operation, const char* body) {
  using Json = nlohmann::json;
  Json result;
  try {
    const std::string op = operation ? operation : "";
    const auto input = Json::parse(body ? body : "{}");
    const std::string address = input.value("address", std::string());
    if (op == "normalize") {
      const auto canonical = kelpie::CanonicalPeerAddress(address);
      result = {{"address", canonical ? Json(*canonical) : Json(nullptr)}, {"loopback", kelpie::IsLoopbackPeer(address)}};
    } else if (op == "safe-host") {
      result = {{"safe", kelpie::IsSafeControlHost(input.value("host", std::string()))}};
    } else {
      kelpie::PeerTrustStore store(path ? std::filesystem::u8path(path) : kelpie::PeerTrustStore::DefaultPath());
      if (op == "check") result = {{"trusted", store.IsTrusted(address)}};
      else if (op == "list") result = {{"computers", store.List()}};
      else if (op == "approve") { store.Approve(address, input.value("name", std::string())); result = {{"success", true}}; }
      else if (op == "revoke") { store.Revoke(address); result = {{"success", true}}; }
      else throw std::runtime_error("Unknown trust operation");
    }
  } catch (const std::exception& error) { result = {{"success", false}, {"error", error.what()}}; }
  const auto text = result.dump();
  auto* output = new (std::nothrow) char[text.size() + 1];
  if (output) std::memcpy(output, text.c_str(), text.size() + 1);
  return output;
}
