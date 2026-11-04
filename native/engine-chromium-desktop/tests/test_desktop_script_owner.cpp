#include "kelpie/desktop_script_owner.h"
#include "kelpie/desktop_http_server.h"
#include "kelpie/desktop_mcp_server.h"
#include "kelpie/desktop_router.h"
#include "kelpie/mcp_registry.h"
#include <httplib.h>
#include <cassert>
#include <thread>
#include <mutex>
#include <iostream>

int main() {
  using kelpie::ScopedDesktopScriptOwner;
  assert(ScopedDesktopScriptOwner::Current().empty());
  {
    ScopedDesktopScriptOwner outer("outer");
    try { ScopedDesktopScriptOwner inner("inner"); throw 1; } catch (...) {}
    assert(ScopedDesktopScriptOwner::Current()=="outer");
    std::thread isolated([] { assert(ScopedDesktopScriptOwner::Current().empty()); });
    isolated.join();
  }
  assert(ScopedDesktopScriptOwner::Current().empty());
  kelpie::DesktopRouter router;
  std::string admitted;
  std::mutex owner_mutex;
  router.Register("play-script",[&](const nlohmann::json&) {
    std::lock_guard lock(owner_mutex);
    const auto owner=ScopedDesktopScriptOwner::Current();
    if(admitted.empty()) admitted=owner;
    return nlohmann::json{{"success",true},{"admitted",!owner.empty()},{"sameOwner",owner==admitted}};
  });
  router.Register("get-script-status",[&](const nlohmann::json&) {
    std::lock_guard lock(owner_mutex);
    return nlohmann::json{{"success",true},{"sameOwner",ScopedDesktopScriptOwner::Current()==admitted}};
  });
  kelpie::McpRegistry registry; kelpie::DesktopMcpServer mcp;
  mcp.SetRouter(&router); mcp.SetRegistry(&registry);
  kelpie::DesktopHttpServer server; server.SetRouter(&router); server.SetMcpServer(&mcp);
  kelpie::DesktopHttpServer::Config config; config.port=0; config.control_token="test-grant"; config.platform="windows";
  assert(server.Start(config));
  httplib::Client client("127.0.0.1",server.bound_port());
  const httplib::Headers headers={{"Authorization","Bearer test-grant"}};
  auto started=client.Post("/v1/play-script",headers,R"({"owner":"forged-body-owner"})","application/json");
  assert(started && started->status==200);
  auto result=nlohmann::json::parse(started->body);
  assert(result["admitted"]==true && result["sameOwner"]==true);
  { std::lock_guard lock(owner_mutex); assert(admitted!="forged-body-owner"); }
  auto status=client.Post("/v1/get-script-status",headers,"{}","application/json");
  assert(status && nlohmann::json::parse(status->body)["sameOwner"]==true);
  const httplib::Headers mcp_headers={{"Authorization","Bearer test-grant"},{"Accept","application/json, text/event-stream"}};
  const auto rpc=client.Post("/mcp",mcp_headers,
    R"({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"kelpie_extension","arguments":{"name":"kelpie_play_script","arguments":{"version":1,"tabId":"test","actions":[{"action":"wait","ms":0}]}}}})",
    "application/json");
  assert(rpc && rpc->status==200);
  const auto envelope=nlohmann::json::parse(rpc->body);
  if(envelope.contains("error")) std::cerr << envelope.at("error").dump() << std::endl;
  assert(!envelope.contains("error"));
  const auto payload=nlohmann::json::parse(envelope.at("result").at("content").at(0).at("text").get<std::string>());
  assert(payload.at("ok")==true && payload.at("value").at("sameOwner")==true);
  const httplib::Headers revoked={{"Authorization","Bearer revoked-grant"}};
  auto denied=client.Post("/v1/get-script-status",revoked,"{}","application/json");
  assert(denied && denied->status==401);
  kelpie::DesktopHttpServer other; other.SetRouter(&router); other.SetMcpServer(&mcp);
  assert(other.Start(config));
  httplib::Client other_client("127.0.0.1",other.bound_port());
  auto foreign=other_client.Post("/v1/get-script-status",headers,"{}","application/json");
  assert(foreign && nlohmann::json::parse(foreign->body)["sameOwner"]==false);
  other.Stop(); server.Stop();
  assert(ScopedDesktopScriptOwner::Current().empty());
}
