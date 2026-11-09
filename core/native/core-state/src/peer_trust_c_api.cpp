#include "kelpie/state_c_api.h"
#include "kelpie/peer_approval.h"
#include <cstring>
#include <memory>
#include <new>
#include <unordered_map>

namespace {
kelpie::PeerApprovalQueue& Queue(const std::string& path) {
  static std::mutex mutex;
  static std::unordered_map<std::string, std::unique_ptr<kelpie::PeerApprovalQueue>> queues;
  std::lock_guard lock(mutex);
  auto& queue = queues[path];
  if (!queue) { queue = std::make_unique<kelpie::PeerApprovalQueue>(std::filesystem::u8path(path)); queue->SetAvailable(true); }
  return *queue;
}
}
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
      auto& queue = Queue(path ? path : kelpie::PeerTrustStore::DefaultPath().u8string());
      const std::string key = input.value("publicKey", std::string());
      const std::string id = input.value("requestId", std::string());
      if (op == "authorize") {
        const auto client = queue.Authorize(address, input.value("token", std::string()));
        result = {{"clientId", client ? Json(*client) : Json(nullptr)}};
      } else if (op == "start") {
        const auto response = queue.Start(address, input.at("body"));
        result = {{"status", response.status}, {"body", response.body}};
      } else if (op == "status") result = queue.Status(address, id);
      else if (op == "pending") result = queue.Pending();
      else if (op == "approve") result = {{"success", queue.Approve(id)}};
      else if (op == "deny") { queue.Deny(id); result = {{"success", true}}; }
      else if (op == "list") {
        auto computers = queue.store().List();
        for (auto& computer : computers) computer.erase("tokenHashes");
        result = {{"computers", computers}};
      } else if (op == "revoke") { queue.store().Revoke(key); result = {{"success", true}}; }
      else throw std::runtime_error("Unknown computer operation");
    }
  } catch (const std::exception& error) { result = {{"success", false}, {"status", "error"}, {"error", error.what()}}; }
  const auto text = result.dump();
  auto* output = new (std::nothrow) char[text.size() + 1];
  if (output) std::memcpy(output, text.c_str(), text.size() + 1);
  return output;
}
