#include "kelpie/desktop_http_server.h"

#include <cassert>
#include <chrono>
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

  server.Stop();
  return 0;
}
