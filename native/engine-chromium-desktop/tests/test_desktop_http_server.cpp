#include "kelpie/desktop_http_server.h"

#include <cassert>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <optional>
#include <thread>

#include <httplib.h>

#include "kelpie/desktop_mcp_server.h"
#include "kelpie/desktop_router.h"
#include "kelpie/mcp_registry.h"

int main() {
  kelpie::DesktopRouter router;
  router.Register("navigate", [](const nlohmann::json& params) {
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
  kelpie::DesktopHttpServer server;
  server.SetRouter(&router);
  server.SetMcpServer(&mcp);
  kelpie::DesktopHttpServer::Config config;
  config.port = 0;
  config.control_token = "test-capability";
  assert(server.Start(config));

  httplib::Client client("127.0.0.1", server.bound_port());
  httplib::Result health;
  for (int attempt = 0; attempt < 50 && !health; ++attempt) {
    health = client.Get("/health");
    if (!health) std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  assert(health && health->status == 200);
  const auto no_token = client.Post("/v1/navigate", "{}", "application/json");
  assert(no_token && no_token->status == 401);

  const httplib::Headers control_headers = {{"Authorization", "Bearer test-capability"}};
  const auto navigate = client.Post("/v1/navigate", control_headers,
                                    R"({"url":"https://example.com"})", "application/json");
  assert(navigate && navigate->status == 200);
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
  return 0;
}
