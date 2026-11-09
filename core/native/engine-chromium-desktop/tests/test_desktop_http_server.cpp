#include "computer_test_identity.h"
#include "kelpie/desktop_http_server.h"

#include <atomic>
#include <cassert>
#include <memory>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <optional>
#include <thread>
#ifndef _WIN32
#include <unistd.h>
#endif

#include <httplib.h>

#include "kelpie/desktop_mcp_server.h"
#include "kelpie/desktop_router.h"
#include "kelpie/mcp_registry.h"

int main() {
  kelpie::DesktopRouter router;
  std::atomic<int> navigations{0};
  router.Register("navigate", [&](const nlohmann::json& params) {
    ++navigations;
    return nlohmann::json{{"success", true}, {"url", params.value("url", std::string())}};
  });
  std::mutex mutation_mutex;
  std::condition_variable mutation_cv;
  bool mutation_entered = false;
  bool release_mutation = false;
  int completed_mutations = 0;
  router.Register("set-home", [&](const nlohmann::json&) {
    std::unique_lock<std::mutex> lock(mutation_mutex);
    mutation_entered = true;
    mutation_cv.notify_all();
    mutation_cv.wait(lock, [&] { return release_mutation; });
    ++completed_mutations;
    return nlohmann::json{{"success", true}};
  });
  kelpie::McpRegistry registry;
  kelpie::DesktopMcpServer mcp;
  mcp.SetRouter(&router);
  mcp.SetRegistry(&registry);
  const kelpie::DesktopMcpServer::Config gateway_config;
  router.Register("browser-control", [&](const nlohmann::json& request) { return mcp.HandleBrowserRequest(request, gateway_config); });
  const auto fixture_root = std::filesystem::temp_directory_path() / ("kelpie-http-trust-" + kelpie::PeerRequestNonce());
  const auto trust_file = fixture_root / "trusted-computers.json";
  kelpie::DesktopHttpServer server(trust_file);
  server.SetRouter(&router);
  server.SetMcpServer(&mcp);
  kelpie::DesktopHttpServer::Config config;
  config.port = 0;
  config.read_timeout_seconds = 1;
  config.control_token = "test-capability";
  assert(server.Start(config));

  httplib::Client client("127.0.0.1", server.bound_port());
  httplib::Result health;
  for (int attempt = 0; attempt < 50 && !health; ++attempt) {
    health = client.Get("/health");
    if (!health) std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  assert(health && health->status == 200);
  // Slow headers and bodies expire on a total budget even while bytes arrive.
  // Another worker must continue serving ordinary local requests meanwhile.
  for (const bool partial_body : {false, true}) {
    const socket_t slow = socket(AF_INET, SOCK_STREAM, 0);
    assert(slow != INVALID_SOCKET);
#ifdef SO_NOSIGPIPE
    const int suppress_sigpipe = 1;
    setsockopt(slow, SOL_SOCKET, SO_NOSIGPIPE, &suppress_sigpipe, sizeof(suppress_sigpipe));
#endif
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_port = htons(static_cast<std::uint16_t>(server.bound_port()));
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    assert(connect(slow, reinterpret_cast<sockaddr*>(&address), sizeof(address)) == 0);
#ifdef _WIN32
    const DWORD receive_timeout = 4000;
#else
    const timeval receive_timeout{4, 0};
#endif
    setsockopt(slow, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char*>(&receive_timeout), sizeof(receive_timeout));
    const std::string prefix = partial_body
        ? "POST /v1/navigate HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: 300\r\n\r\n{"
        : "POST /v1/navigate HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Slow: ";
    assert(send(slow, prefix.data(), static_cast<int>(prefix.size()), 0) > 0);
    std::atomic<bool> finished{false};
    std::thread writer([&] {
      while (!finished) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
#ifdef MSG_NOSIGNAL
        const int flags = MSG_NOSIGNAL;
#else
        const int flags = 0;
#endif
        if (send(slow, " ", 1, flags) <= 0) break;
      }
    });
    const auto concurrent_health = client.Get("/health");
    assert(concurrent_health && concurrent_health->status == 200);
    char response[4096]{};
    const auto count = recv(slow, response, sizeof(response), 0);
    finished = true;
    writer.join();
    assert(count >= 0);  // a timeout (-1) would mean the drip kept the worker alive
    assert(navigations == 0);
#ifdef _WIN32
    closesocket(slow);
#else
    close(slow);
#endif
  }
  const auto no_token = client.Post("/v1/navigate", "{}", "application/json");
  assert(no_token && no_token->status == 200);

  const httplib::Headers control_headers = {{"Authorization", "Bearer test-capability"}};
  const auto navigate = client.Post("/v1/navigate", control_headers,
                                    R"({"url":"https://example.com"})", "application/json");
  assert(navigate && navigate->status == 200);
  const auto core_denied = client.Post("/v1/browser-control", "{}", "application/json");
  assert(core_denied && core_denied->status == 200);
  const auto core = client.Post("/v1/browser-control", control_headers,
    R"({"version":1,"method":"tab.goto","tabId":"a","params":{"url":"https://example.com"}})", "application/json");
  assert(core && core->status == 200 && nlohmann::json::parse(core->body)["ok"] == true);
  const auto invalid_core = client.Post("/v1/browser-control", control_headers,
    R"({"version":1,"method":"evaluate","params":{"script":"SECRET"}})", "application/json");
  assert(invalid_core && invalid_core->status == 200 && nlohmann::json::parse(invalid_core->body)["ok"] == false);
  const auto get_mcp = client.Get("/mcp");
  assert(get_mcp && get_mcp->status == 405);

  const httplib::Headers mcp_headers = {
      {"Authorization", "Bearer test-capability"},
      {"Accept", "application/json, text/event-stream"},
      {"MCP-Protocol-Version", "2025-06-18"},
  };
  const auto initialize = client.Post("/mcp", mcp_headers,
      R"({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25"}})",
      "application/json");
  assert(initialize && initialize->status == 200);
  assert(nlohmann::json::parse(initialize->body)["result"]["protocolVersion"] == "2025-06-18");
  const auto notification = client.Post("/mcp", mcp_headers,
      R"({"jsonrpc":"2.0","method":"tools/list"})", "application/json");
  assert(notification && notification->status == 202 && notification->body.empty());

  // Use the machine's real LAN source address when one is available. The UDP
  // connect only selects a route; it sends no datagram to the documentation IP.
  const socket_t route = socket(AF_INET, SOCK_DGRAM, 0);
  sockaddr_in destination{};
  destination.sin_family = AF_INET; destination.sin_port = htons(9);
  destination.sin_addr.s_addr = htonl(0xc0000201);
  sockaddr_in local{};
  socklen_t local_size = sizeof(local);
  if (route != INVALID_SOCKET && connect(route, reinterpret_cast<sockaddr*>(&destination), sizeof(destination)) == 0 &&
      getsockname(route, reinterpret_cast<sockaddr*>(&local), &local_size) == 0 && ntohl(local.sin_addr.s_addr) >> 24 != 127) {
    char host[INET_ADDRSTRLEN]{};
    assert(inet_ntop(AF_INET, &local.sin_addr, host, sizeof(host)));
    httplib::Client remote(host, server.bound_port());
    remote.set_connection_timeout(2);
    const auto denied = remote.Post("/v1/navigate", {{"X-Forwarded-For", "127.0.0.1"}}, "{}", "application/json");
    assert(denied && denied->status == 401);
    const auto old_cli = remote.Post("/v1/pair", R"({"clientId":"remote"})", "application/json");
    assert(old_cli && old_cli->status == 400);
    server.approvals().SetAvailable(true);
    const Identity computer(7), stranger(8);
    const auto start = [&](const Identity& identity, const std::string& label) {
      auto body = identity.Body(label);
      const auto challenge = remote.Post("/v1/pair", body.dump(), "application/json");
      assert(challenge && challenge->status == 202);
      const auto id = Json::parse(challenge->body)["requestId"].get<std::string>();
      body["requestId"] = id; body["computerSignature"] = identity.Sign(id);
      const auto proven = remote.Post("/v1/pair", body.dump(), "application/json");
      assert(proven && proven->status == 202);
      return id;
    };
    const auto first_id = start(computer, "tool-a"), second_id = start(computer, "tool-b");
    const auto stolen = client.Get("/v1/pair/status?requestId=" + first_id);
    assert(stolen && Json::parse(stolen->body)["status"] == "not_found");
    assert(server.approvals().Approve(first_id));
    const auto approved = remote.Get("/v1/pair/status?requestId=" + first_id);
    assert(approved && Json::parse(approved->body)["status"] == "approved");
    const auto token = Json::parse(approved->body)["token"].get<std::string>();
    const auto second = remote.Get("/v1/pair/status?requestId=" + second_id);
    assert(second && Json::parse(second->body)["status"] == "approved");
    const httplib::Headers authorized = {{"Authorization", "Bearer " + token}};
    const auto permitted = remote.Post("/v1/navigate", authorized, "{}", "application/json");
    assert(permitted && permitted->status == 200);
    const auto no_token = remote.Post("/v1/navigate", "{}", "application/json");
    assert(no_token && no_token->status == 401); // IP did not acquire authority.
    const auto unknown = start(stranger, "same-ip-other-computer");
    assert(server.approvals().Pending()["publicKey"] == stranger.key);
    server.approvals().Deny(unknown);
    const httplib::Headers remote_mcp = {{"Accept", "application/json, text/event-stream"}, {"Authorization", "Bearer " + token}};
    const auto mcp_allowed = remote.Post("/mcp", remote_mcp, R"({"jsonrpc":"2.0","id":4,"method":"initialize"})", "application/json");
    assert(mcp_allowed && mcp_allowed->status == 200);
    kelpie::DesktopHttpServer restarted(trust_file);
    restarted.SetRouter(&router); restarted.SetMcpServer(&mcp);
    assert(restarted.Start(config));
    httplib::Client after_restart(host, restarted.bound_port());
    const auto reused = after_restart.Post("/v1/navigate", authorized, "{}", "application/json");
    assert(reused && reused->status == 200 && restarted.approvals().Pending().is_null());
    server.approvals().store().Revoke(computer.key);
    const auto revoked = after_restart.Post("/v1/navigate", authorized, "{}", "application/json");
    assert(revoked && revoked->status == 401);
    const auto mcp_revoked = remote.Post("/mcp", remote_mcp, R"({"jsonrpc":"2.0","id":5,"method":"initialize"})", "application/json");
    assert(mcp_revoked && mcp_revoked->status == 401);
    restarted.Stop();
  }
  if (route != INVALID_SOCKET) {
#ifdef _WIN32
    closesocket(route);
#else
    close(route);
#endif
  }

  // A close gate must allow work admitted before listener shutdown to finish,
  // but it must not admit a later durable-state mutation before persistence.
  std::optional<httplib::Result> in_flight;
  std::thread mutation([&] {
    httplib::Client mutation_client("127.0.0.1", server.bound_port());
    in_flight = mutation_client.Post("/v1/set-home", control_headers, "{}", "application/json");
  });
  {
    std::unique_lock<std::mutex> lock(mutation_mutex);
    assert(mutation_cv.wait_for(lock, std::chrono::seconds(2), [&] { return mutation_entered; }));
  }
  server.BeginDrain();
  // Retried native close requests must not close the same listener twice.
  server.BeginDrain();
  assert(!server.IsDrained());
  httplib::Client late_client("127.0.0.1", server.bound_port());
  const auto late_mutation = late_client.Post("/v1/set-home", control_headers, "{}", "application/json");
  assert(!late_mutation || late_mutation->status == 503);
  {
    std::lock_guard<std::mutex> lock(mutation_mutex);
    assert(completed_mutations == 0);
    release_mutation = true;
  }
  mutation_cv.notify_all();
  mutation.join();
  assert(in_flight && *in_flight && (*in_flight)->status == 200);
  {
    std::lock_guard<std::mutex> lock(mutation_mutex);
    assert(completed_mutations == 1);
  }
  for (int attempt = 0; attempt < 50 && !server.IsDrained(); ++attempt) {
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  assert(server.IsDrained());

  server.Stop();

  // RAII shutdown must join an admitted handler before releasing the server
  // object. This is the same barrier DesktopApp uses before CEF owner teardown.
  kelpie::DesktopRouter destructor_router;
  std::mutex destructor_mutex;
  std::condition_variable destructor_cv;
  bool destructor_entered = false;
  bool release_destructor = false;
  destructor_router.Register("set-home", [&](const nlohmann::json&) {
    std::unique_lock<std::mutex> lock(destructor_mutex);
    destructor_entered = true;
    destructor_cv.notify_all();
    destructor_cv.wait(lock, [&] { return release_destructor; });
    return nlohmann::json{{"success", true}};
  });
  kelpie::McpRegistry destructor_registry;
  kelpie::DesktopMcpServer destructor_mcp;
  destructor_mcp.SetRouter(&destructor_router);
  destructor_mcp.SetRegistry(&destructor_registry);
  auto destructor_server = std::make_unique<kelpie::DesktopHttpServer>();
  destructor_server->SetRouter(&destructor_router);
  destructor_server->SetMcpServer(&destructor_mcp);
  assert(destructor_server->Start(config));
  const int destructor_port = destructor_server->bound_port();
  std::optional<httplib::Result> destructor_result;
  std::thread destructor_request([&] {
    httplib::Client destructor_client("127.0.0.1", destructor_port);
    destructor_result = destructor_client.Post("/v1/set-home", control_headers, "{}", "application/json");
  });
  {
    std::unique_lock<std::mutex> lock(destructor_mutex);
    assert(destructor_cv.wait_for(lock, std::chrono::seconds(2), [&] { return destructor_entered; }));
  }
  std::atomic<bool> destructor_finished = false;
  std::thread destroy([&] {
    destructor_server.reset();
    destructor_finished.store(true);
  });
  std::this_thread::sleep_for(std::chrono::milliseconds(25));
  assert(!destructor_finished.load());
  {
    std::lock_guard<std::mutex> lock(destructor_mutex);
    release_destructor = true;
  }
  destructor_cv.notify_all();
  destructor_request.join();
  destroy.join();
  assert(destructor_result && *destructor_result && (*destructor_result)->status == 200);
  assert(destructor_finished.load());

  std::filesystem::remove_all(fixture_root);
  return 0;
}
