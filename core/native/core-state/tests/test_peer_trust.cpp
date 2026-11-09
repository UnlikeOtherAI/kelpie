#include "kelpie/peer_approval.h"
#include "kelpie/state_c_api.h"
extern "C" {
#include "ed25519.h"
}
#include <array>
#include <cassert>
#include <filesystem>
#include <fstream>
#include <thread>
#include <vector>

#include "computer_test_identity.h"
int main() {
  const auto root = std::filesystem::temp_directory_path() / ("kelpie-computer-" + kelpie::PeerRequestNonce());
  const auto path = root / "trusted-computers.json";
  std::filesystem::create_directories(root);
  Identity computer(1), other(2);
  assert(!kelpie::IsComputerKey(std::string(64, '0')));
  assert(!kelpie::IsComputerKey("01" + std::string(62, '0')));
  assert(!kelpie::VerifyComputerSignature(computer.key, "wrong-challenge", computer.Sign("original")));
  kelpie::PeerApprovalQueue queue(path);
  queue.SetAvailable(true);
  assert(queue.Authorize("127.0.0.1", "") == "localhost");
  assert(queue.Authorize("::1", "") == "localhost");
  assert(!queue.Authorize("192.0.2.1", ""));
  assert(queue.Start("192.0.2.1", {{"clientId", "old-cli"}}).status == 400);
  auto initial = queue.Start("192.0.2.1", computer.Body());
  auto id = initial.body["requestId"].get<std::string>();
  assert(queue.Pending().is_null() && !queue.Approve(id)); // Possession before prompting.
  auto proof = computer.Body(); proof["requestId"] = id; proof["computerSignature"] = other.Sign(id);
  assert(queue.Start("192.0.2.1", proof).status == 403);
  proof["computerSignature"] = computer.Sign(id);
  assert(queue.Start("192.0.2.1", proof).status == 202);
  assert(queue.Start("192.0.2.1", proof).status == 403); // No proof replay.
  assert(queue.Pending()["publicKey"] == computer.key);
  const auto concurrent = computer.Start(queue, "192.0.2.1", "another-tool");
  assert(queue.Status("192.0.2.2", id)["status"] == "not_found");
  assert(queue.Approve(id)); // One approval resolves every proven waiter for this key.
  assert(queue.Pending().is_null());
  const auto first = queue.Status("192.0.2.1", id);
  const auto second = queue.Status("192.0.2.1", concurrent);
  assert(first["status"] == "approved" && second["status"] == "approved");
  const auto token = first["token"].get<std::string>();
  assert(queue.Authorize("203.0.113.7", token) == computer.key);
  assert(queue.Authorize("192.0.2.1", second["token"]) == computer.key);
  assert(queue.Status("192.0.2.1", id)["status"] == "not_found");
  kelpie::PeerApprovalQueue restarted(path);
  restarted.SetAvailable(true);
  assert(restarted.Authorize("203.0.113.7", token) == computer.key);
  const auto moved = computer.Start(restarted, "203.0.113.7", "fresh-client-id");
  assert(restarted.Pending().is_null()); // Changed IP/client/port does not ask again.
  assert(restarted.Status("203.0.113.7", moved)["status"] == "approved");
  assert(!restarted.Authorize("192.0.2.1", "")); // Old IP has no authority.
  const auto stranger = other.Start(restarted, "192.0.2.1");
  assert(restarted.Pending()["publicKey"] == other.key); // Another key at the same IP asks.
  restarted.Deny(stranger);
  assert(restarted.Status("192.0.2.1", stranger)["status"] == "denied");
  assert(restarted.Start("198.51.100.8", other.Body()).status == 403); // Denial follows key too.
  restarted.store().Revoke(computer.key);
  assert(!queue.Authorize("203.0.113.7", token)); // Even a pre-existing instance observes revocation.
  const auto revoked = computer.Start(restarted, "203.0.113.7");
  assert(!restarted.Pending().is_null());
  assert(restarted.Status("203.0.113.7", revoked)["status"] == "pending");
  // An OS dialog may cover the native gate longer than the proof deadline.
  // Keep the displayed, verified identity answerable until the human decides.
  std::int64_t human_now = 1000;
  kelpie::PeerApprovalQueue waiting(root / "waiting.json", [&] { return human_now; });
  waiting.SetAvailable(true);
  const auto displayed = computer.Start(waiting, "192.0.2.20");
  assert(waiting.Pending()["requestId"] == displayed);
  const auto undisplayed = other.Start(waiting, "192.0.2.21");
  human_now += 600001;
  assert(waiting.Status("192.0.2.20", displayed)["status"] == "pending");
  assert(waiting.Status("192.0.2.21", undisplayed)["status"] == "not_found");
  assert(waiting.Pending()["requestId"] == displayed);
  assert(waiting.Approve(displayed));
  assert(waiting.Status("192.0.2.20", displayed)["status"] == "approved");
  const auto declined = other.Start(waiting, "192.0.2.21");
  assert(waiting.Pending()["requestId"] == declined);
  human_now += 600001;
  waiting.Deny(declined);
  assert(waiting.Status("192.0.2.21", declined)["status"] == "denied");
  // Expiry, replay bounds and failed persistence must not grant authority.
  std::int64_t now = 1000;
  kelpie::PeerApprovalQueue bounded(root / "bounded.json", [&] { return now; });
  bounded.SetAvailable(true);
  const auto expired = bounded.Start("192.0.2.10", computer.Body());
  const auto expired_id = expired.body["requestId"].get<std::string>();
  now += 300001;
  auto stale = computer.Body(); stale["requestId"] = expired_id; stale["computerSignature"] = computer.Sign(expired_id);
  assert(bounded.Start("192.0.2.10", stale).status == 403 && bounded.Pending().is_null());
  for (int i = 0; i < 32; ++i) assert(bounded.Start("192.0.2.10", computer.Body()).status == 202);
  assert(bounded.Start("192.0.2.10", computer.Body()).status == 429);
  assert(bounded.Start("192.0.2.11", other.Body()).status == 202);
  now += 300001;
  assert(bounded.Start("192.0.2.10", computer.Body()).status == 202);
  std::ofstream(root / "not-a-directory") << "blocked storage";
  kelpie::PeerApprovalQueue blocked(root / "not-a-directory" / "trust.json");
  blocked.SetAvailable(true);
  const auto unsaved = computer.Start(blocked, "192.0.2.1");
  assert(!blocked.Approve(unsaved) && !blocked.Authorize("192.0.2.1", token));
  assert(!blocked.Pending().is_null());
  // Independent store instances cannot overwrite each other's changes.
  std::vector<std::thread> writers;
  for (unsigned char i = 10; i < 18; ++i) writers.emplace_back([&, i] {
    kelpie::PeerTrustStore(root / "concurrent.json").Approve(Identity(i).key, "computer", "192.0.2.1");
  });
  for (auto& writer : writers) writer.join();
  assert(kelpie::PeerTrustStore(root / "concurrent.json").List().size() == 8);
  std::ifstream vectors(PEER_ADDRESS_FIXTURES);
  for (const auto& row : Json::parse(vectors)) {
    const auto address = kelpie::CanonicalPeerAddress(row.at("input"));
    assert((address ? Json(*address) : Json(nullptr)) == row.at("address"));
    assert(kelpie::IsLoopbackPeer(row.at("input")) == row.at("loopback"));
  }
  auto* response = kelpie_peer_trust_request(path.u8string().c_str(), "normalize", R"({"address":"::ffff:127.0.0.1"})");
  assert(response && Json::parse(response)["address"] == "127.0.0.1"); kelpie_free_string(response);
  // IP-only state is not upgraded into a key grant; unsupported schemas remain untouched.
  std::ofstream(path, std::ios::trunc) << R"({"version":1,"computers":[{"address":"192.0.2.1"}]})";
  assert(!queue.store().IsTrusted(computer.key));
  std::ofstream(path, std::ios::trunc) << R"({"version":99,"computers":[]})";
  assert(!restarted.Approve(revoked));
  std::ofstream(path, std::ios::trunc) << "broken";
  assert(!queue.Authorize("203.0.113.7", token));
  assert(restarted.Approve(revoked)); // Explicit reapproval archives a corrupt file.
  assert(restarted.store().IsTrusted(computer.key));
  std::filesystem::remove_all(root);
}
