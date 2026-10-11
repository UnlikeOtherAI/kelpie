#include "kelpie/connect.h"
#include <nlohmann/json.hpp>
#include <cassert>
#include <string>
using Json = nlohmann::json;
const std::string id = "a0000000-0000-4000-8000-000000000001";
const std::string generation = "b0000000-0000-4000-8000-000000000001";
Json Execute(KelpieConnectRef client, const char* op, const Json& body) {
  auto* raw = kelpie_connect_execute(client, op, body.dump().c_str());
  assert(raw);
  auto result = Json::parse(raw);
  kelpie_connect_free(raw);
  return result;
}
Json Welcome(KelpieConnectRef client, std::string gen = generation) {
  return Execute(client, "receive", {{"type", "welcome"}, {"protocol", 1},
      {"deviceId", id}, {"generation", gen}});
}
int main() {
  auto* client = kelpie_connect_create("", "issuer/subject");
  assert(client);
  Welcome(client);
  Json command = {{"type", "command"}, {"generation", generation}, {"jobId", id},
      {"attemptId", id}, {"seq", 1}, {"operation", "click"}, {"tabId", "tab"},
      {"tabVersion", "document"}, {"deadline", "2026-10-11T10:00:00Z"},
      {"input", {{"selector", "#submit"}}}};
  const auto first = Execute(client, "receive", command);
  assert(first["decision"]["kind"] == "command");
  assert(Execute(client, "receive", command)["decision"]["kind"] == "duplicate");
  const std::string unseen = "a0000000-0000-4000-8000-000000000002";
  Json cancellation = {{"type", "cancel"}, {"generation", generation}, {"jobId", unseen}, {"attemptId", unseen}, {"seq", 2}};
  const auto receipt = Execute(client, "receive", cancellation);
  assert(receipt["decision"]["kind"] == "receipt"); // Does not cancel the active first command.
  assert(receipt["decision"]["frames"][0]["state"] == "cancelled");
  assert(receipt["decision"]["frames"][0]["seq"] == 2);
  assert(Execute(client, "receive", cancellation)["decision"]["frames"][0]["state"] == "cancelled");
  auto cancelled_command = command;
  cancelled_command["jobId"] = cancelled_command["attemptId"] = unseen;
  assert(Execute(client, "receive", cancelled_command)["decision"]["kind"] == "duplicate");
  auto malformed_cancel = cancellation;
  malformed_cancel["seq"] = 1;
  assert(!kelpie_connect_execute(client, "receive", malformed_cancel.dump().c_str()));
  malformed_cancel = cancellation;
  malformed_cancel["unexpected"] = "not permitted";
  assert(!kelpie_connect_execute(client, "receive", malformed_cancel.dump().c_str()));
  auto* restored_cancel = kelpie_connect_create(receipt["state"].dump().c_str(), "issuer/subject");
  assert(restored_cancel);
  Welcome(restored_cancel);
  assert(Execute(restored_cancel, "receive", cancelled_command)["decision"]["kind"] == "duplicate");
  kelpie_connect_destroy(restored_cancel);
  auto reused = command;
  reused["input"]["selector"] = "#different";
  assert(!kelpie_connect_execute(client, "receive", reused.dump().c_str()));
  auto unpinned = command;
  unpinned["tabVersion"] = nullptr;
  assert(!kelpie_connect_execute(client, "receive", unpinned.dump().c_str()));
  auto stale = command;
  stale["generation"] = id;
  assert(Execute(client, "receive", stale)["decision"]["kind"] == "ignored");
  kelpie_connect_destroy(client);
  client = kelpie_connect_create(first["state"].dump().c_str(), "issuer/subject");
  auto recovery = Welcome(client);
  assert(recovery["decision"]["frames"][0]["state"] == "failed");
  assert(recovery["decision"]["frames"][0]["error"].get<std::string>().find("UNKNOWN_EFFECTS") == 0);
  assert(Execute(client, "receive", command)["decision"]["kind"] == "duplicate");
  auto ack = Json{{"type", "ack"}, {"generation", generation}, {"jobId", id}, {"attemptId", id}, {"seq", 1}};
  Execute(client, "receive", ack);
  assert(!Welcome(client)["decision"]["frames"].empty()); // Delayed accepted ack cannot erase completion.
  ack["seq"] = 2;
  const auto acknowledged = Execute(client, "receive", ack);
  assert(Welcome(client)["decision"]["frames"].empty());
  assert(Execute(client, "receive", command)["decision"]["kind"] == "duplicate");
  kelpie_connect_destroy(client);
  client = kelpie_connect_create(acknowledged["state"].dump().c_str(), "issuer/other");
  Welcome(client);
  assert(Execute(client, "receive", command)["decision"]["kind"] == "command");
  auto terminal = Execute(client, "complete", {{"jobId", id}, {"attemptId", id},
      {"state", "completed"}, {"output", {{"success", true}}}});
  kelpie_connect_destroy(client);
  client = kelpie_connect_create(terminal["state"].dump().c_str(), "issuer/other");
  const auto reconnected = Welcome(client, id);
  assert(reconnected["decision"]["frames"][0]["generation"] == id);
  assert(reconnected["decision"]["frames"][0]["state"] == "completed");
  cancellation["generation"] = id;
  cancellation["jobId"] = cancellation["attemptId"] = id;
  const auto completed_receipt = Execute(client, "receive", cancellation);
  assert(completed_receipt["decision"]["kind"] == "receipt");
  assert(completed_receipt["decision"]["frames"][0]["state"] == "completed");
  ack["generation"] = id;
  Execute(client, "receive", ack);
  const auto acked_receipt = Execute(client, "receive", cancellation);
  assert(acked_receipt["decision"]["frames"][0]["state"] == "completed");
  assert(!acked_receipt["decision"]["frames"][0].contains("output"));
  kelpie_connect_destroy(client);
  assert(!kelpie_connect_create("broken", "issuer/subject"));
}
