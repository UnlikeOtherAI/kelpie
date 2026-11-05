#include "kelpie/peer_approval.h"
#include "kelpie/state_c_api.h"
#include <cassert>
#include <filesystem>
#include <fstream>
#include <thread>
#include <vector>
#ifdef _WIN32
#include <windows.h>
#else
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#endif

using kelpie::PeerTrustStore;
using Json = nlohmann::json;

int main(int argc, char** argv) {
  if (argc == 4 && std::string(argv[1]) == "--approve") {
    PeerTrustStore(std::filesystem::u8path(argv[2])).Approve(argv[3], "parallel child");
    return 0;
  }
  const auto root = std::filesystem::temp_directory_path() / ("kelpie-trust-" + kelpie::PeerRequestNonce());
  const auto path = root / "trusted-computers.json";
  std::filesystem::create_directories(root);
  // The Swift/JNI response uses the same new[]/delete[] ownership as the other
  // state C APIs. This also exercises the ownership boundary under sanitizers.
  for (int index = 0; index < 100; ++index) {
    auto* response = kelpie_peer_trust_request(nullptr, "normalize", R"({"address":"::ffff:127.0.0.1"})");
    assert(response && Json::parse(response).at("address") == "127.0.0.1");
    kelpie_free_string(response);
  }
  std::ifstream vectors(PEER_ADDRESS_FIXTURES);
  for (const auto& row : Json::parse(vectors)) {
    const auto address = kelpie::CanonicalPeerAddress(row.at("input"));
    assert((address ? Json(*address) : Json(nullptr)) == row.at("address"));
    assert(kelpie::IsLoopbackPeer(row.at("input")) == row.at("loopback"));
  }
  for (const auto& host : {"127.0.0.1:8420", "localhost:8420", "[::1]:8420", "192.168.1.90"}) assert(kelpie::IsSafeControlHost(host));
  for (const auto& host : {"evil.example:8420", "localhost.evil:8420", "127.0.0.1.evil", "[::1]:", "localhost@evil"}) assert(!kelpie::IsSafeControlHost(host));

  PeerTrustStore first(path), second(path);
  assert(first.IsTrusted("127.2.3.4"));
  assert(first.IsTrusted("[::ffff:127.0.0.1]"));
  assert(!first.IsTrusted("192.168.1.90"));
  first.Approve("[::ffff:192.168.1.90]", "computer");
  assert(second.IsTrusted("192.168.1.90"));
  assert(!second.IsTrusted("192.168.1.91"));
  second.Revoke("192.168.1.90");
  assert(!first.IsTrusted("192.168.1.90"));

  // Independent processes use the same lock around reload/modify/replace.
#ifdef _WIN32
  std::vector<PROCESS_INFORMATION> children;
  for (int index = 1; index <= 8; ++index) {
    auto command = L"\"" + std::filesystem::absolute(argv[0]).wstring() + L"\" --approve \"" + path.wstring() + L"\" 192.168.2." + std::to_wstring(index);
    STARTUPINFOW startup{}; startup.cb = sizeof(startup);
    PROCESS_INFORMATION child{};
    assert(CreateProcessW(nullptr, command.data(), nullptr, nullptr, FALSE, 0, nullptr, nullptr, &startup, &child));
    children.push_back(child);
  }
  for (auto& child : children) {
    assert(WaitForSingleObject(child.hProcess, 10000) == WAIT_OBJECT_0);
    DWORD code = 1; GetExitCodeProcess(child.hProcess, &code); assert(code == 0);
    CloseHandle(child.hThread); CloseHandle(child.hProcess);
  }
#else
  std::vector<pid_t> children;
  for (int index = 1; index <= 8; ++index) {
    const auto child = fork(); assert(child >= 0);
    if (child == 0) { PeerTrustStore(path).Approve("192.168.2." + std::to_string(index), "parallel child"); _exit(0); }
    children.push_back(child);
  }
  for (const auto child : children) { int status; assert(waitpid(child, &status, 0) == child); assert(WIFEXITED(status) && WEXITSTATUS(status) == 0); }
  struct stat attributes{}; assert(stat(path.c_str(), &attributes) == 0); assert((attributes.st_mode & 0777) == 0600);
#endif
  assert(first.List().size() == 8);
  // A stale instance cannot restore an address revoked by another instance.
  second.Revoke("192.168.2.1");
  first.Approve("192.168.3.1", "another");
  assert(!second.IsTrusted("192.168.2.1"));

  kelpie::PeerApprovalQueue queue(path);
  assert(queue.Start("192.168.5.1", {{"clientId", "a"}}).status == 409);
  queue.SetAvailable(true);
  assert(queue.Start("192.168.5.1", {{"clientId", "a"}, {"clientName", 7}}).status == 400);
  const auto a = queue.Start("192.168.5.1", {{"clientId", "same-id"}, {"clientName", "a"}});
  const auto b = queue.Start("::ffff:192.168.5.1", {{"clientId", "same-id"}, {"clientName", "b"}});
  assert(a.status == 202 && b.status == 202 && a.body["requestId"] != b.body["requestId"]);
  assert(queue.Status("192.168.5.2", a.body["requestId"])["status"] == "not_found");
  assert(queue.Approve(a.body["requestId"]));
  assert(queue.Pending().is_null());
  assert(queue.Status("192.168.5.1", a.body["requestId"])["status"] == "approved");
  assert(queue.Status("192.168.5.1", b.body["requestId"])["status"] == "approved");
  assert(queue.Status("192.168.5.1", b.body["requestId"])["status"] == "not_found");
  const auto reused = queue.Start("192.168.5.1", {{"clientId", "new-client"}});
  assert(reused.body["approvalRequired"] == false && queue.Pending().is_null());
  second.Revoke("192.168.5.1");
  assert(queue.Status("192.168.5.1", reused.body["requestId"])["status"] == "denied");
  assert(!queue.IsTrusted("192.168.5.1"));
  assert(queue.Start("192.168.5.2", {{"clientId", "account"}, {"account", true}}).status == 409);
  assert(queue.Pending().is_null() && !queue.IsTrusted("192.168.5.2"));
  const auto denied = queue.Start("192.168.5.3", {{"clientId", "denied"}});
  queue.Deny(denied.body["requestId"]);
  assert(queue.Start("192.168.5.3", {{"clientId", "retry"}}).status == 403);
  assert(queue.Status("192.168.5.3", denied.body["requestId"])["status"] == "denied");
  second.Approve("192.168.5.3", "explicit approval in another process");
  assert(queue.Start("192.168.5.3", {{"clientId", "approved-after-denial"}}).body["approvalRequired"] == false);
  std::string multibyte;
  for (int index = 0; index < 100; ++index) multibyte += "\xe2\x98\x83";
  const auto label = kelpie::SanitizePeerLabel(multibyte);
  assert(label.size() <= 256 && label.size() % 3 == 0);
  assert((!Json{{"name", label}}.dump().empty()));

  std::int64_t time = 1000;
  kelpie::PeerApprovalQueue bounded(path, [&] { return time; });
  bounded.SetAvailable(true);
  const auto expired = bounded.Start("192.0.2.90", {{"clientId", "expired"}});
  time += 300001;
  assert(!bounded.Approve(expired.body["requestId"]));
  assert(bounded.Pending().is_null() && !bounded.IsTrusted("192.0.2.90"));
  for (int index = 1; index <= 32; ++index)
    assert(bounded.Start("192.0.2.90", {{"clientId", "bounded"}}).status == 202);
  assert(bounded.Start("192.0.2.90", {{"clientId", "overflow"}}).status == 429);
  assert(bounded.Start("192.0.2.99", {{"clientId", "another-computer"}}).status == 202);
  for (int index = 1; index <= 6; ++index)
    assert(bounded.Start("192.0.2." + std::to_string(index), {{"clientId", "another"}}).status == 202);
  assert(bounded.Start("192.0.2.7", {{"clientId", "global-bound"}}).status == 429);
  time += 300001;
  assert(bounded.Start("192.0.2.99", {{"clientId", "recovered"}}).status == 202);

  std::ofstream(path, std::ios::trunc) << "corrupt";
  assert(!first.IsTrusted("192.168.3.1"));
  assert(first.IsTrusted("::1"));
  first.Approve("192.168.3.2", "fresh explicit approval");
  assert(first.IsTrusted("192.168.3.2"));
  assert(!first.IsTrusted("192.168.3.1"));
  bool archived = false;
  for (const auto& entry : std::filesystem::directory_iterator(root))
    archived |= entry.path().filename().string().find(".corrupt-") != std::string::npos;
  assert(archived);
  std::ofstream(path, std::ios::trunc) << R"({"version":2,"computers":[]})";
  bool failed = false;
  try { first.Approve("192.168.3.3", "unsupported schema"); } catch (...) { failed = true; }
  assert(failed && !first.IsTrusted("192.168.3.3"));
  std::filesystem::remove_all(root);
  return 0;
}
