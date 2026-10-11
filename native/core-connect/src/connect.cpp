#include "kelpie/connect.h"
#include <nlohmann/json.hpp>
#include <cstdlib>
#include <cstring>
#include <map>
#include <memory>
#include <set>
#include <stdexcept>
#include <string>

using Json = nlohmann::json;
namespace {
constexpr std::size_t kMaxFrame = 1024 * 1024;
constexpr std::size_t kMaxOutput = 768 * 1024;
constexpr std::size_t kMaxJournal = 32 * 1024 * 1024;
const std::set<std::string> kOperations = {
    "tabs", "open", "navigate", "snapshot", "click", "type", "scroll",
    "back", "forward", "reload", "extract"};
std::string Text(const Json& value, const char* key) {
  if (!value.contains(key) || !value[key].is_string()) throw std::invalid_argument(key);
  return value[key].get<std::string>();
}
bool UUID(const std::string& value) {
  if (value.size() != 36) return false;
  for (std::size_t i = 0; i < value.size(); ++i) {
    if (i == 8 || i == 13 || i == 18 || i == 23) {
      if (value[i] != '-') return false;
    } else if (!((value[i] >= '0' && value[i] <= '9') ||
                 (value[i] >= 'a' && value[i] <= 'f') ||
                 (value[i] >= 'A' && value[i] <= 'F'))) return false;
  }
  return true;
}
std::string Key(const Json& value) {
  const auto job = Text(value, "jobId");
  const auto attempt = Text(value, "attemptId");
  if (!UUID(job) || !UUID(attempt)) throw std::invalid_argument("Invalid job identity");
  return job + ":" + attempt;
}
bool Terminal(const std::string& state) {
  return state == "completed" || state == "failed" || state == "cancelled";
}
Json Event(const Json& command, const std::string& state) {
  return {{"type", "event"}, {"jobId", command.at("jobId")},
      {"attemptId", command.at("attemptId")}, {"seq", command.at("seq")}, {"state", state}};
}
}

struct KelpieConnect {
  Json journal = {{"version", 1}, {"owner", ""}, {"jobs", Json::object()}};
  std::string generation;

  Json Frames(const std::string& current) {
    Json frames = Json::array();
    for (const auto& job : journal["jobs"]) {
      if (!job.contains("event") || job.value("acked", false)) continue;
      auto event = job["event"];
      event["generation"] = current;
      frames.push_back(event);
    }
    return frames;
  }

  Json Receive(const Json& frame) {
    const auto type = Text(frame, "type");
    if (type == "welcome") {
      if (frame.at("protocol") != 1 || !UUID(Text(frame, "generation")) ||
          !UUID(Text(frame, "deviceId"))) throw std::invalid_argument("Invalid welcome");
      generation = Text(frame, "generation");
      return {{"kind", "welcome"}, {"frames", Frames(generation)}};
    }
    if (generation.empty() || Text(frame, "generation") != generation)
      return {{"kind", "ignored"}};
    if (type != "command" && type != "ack" && type != "cancel")
      throw std::invalid_argument("Unsupported frame");
    const auto key = Key(frame);
    const auto seq = frame.at("seq").get<std::int64_t>();
    if (seq <= 0) throw std::invalid_argument("Invalid sequence");
    auto& jobs = journal["jobs"];
    if (type == "ack") {
      if (jobs.contains(key) && jobs[key].contains("event") &&
          jobs[key]["event"].at("seq") == seq) {
        jobs[key]["acked"] = true;
        // Keep identity tombstones so duplicated mutations never execute again.
        jobs[key].erase("event");
      }
      return {{"kind", "ack"}};
    }
    if (type == "cancel") {
      if (!jobs.contains(key) || jobs[key].value("terminal", false))
        return {{"kind", "ignored"}};
      auto event = Event(jobs[key]["command"], "cancelled");
      jobs[key]["event"] = event;
      jobs[key]["terminal"] = true;
      event["generation"] = generation;
      return {{"kind", "cancel"}, {"jobId", frame["jobId"]},
          {"attemptId", frame["attemptId"]}, {"frames", Json::array({event})}};
    }
    const auto operation = Text(frame, "operation");
    if (!kOperations.count(operation) || !frame.at("input").is_object())
      throw std::invalid_argument("Invalid command");
    Text(frame, "deadline"); // Platform validates wall-clock expiry before dispatch.
    if (operation != "tabs" && operation != "open") {
      if (Text(frame, "tabId").empty() || Text(frame, "tabVersion").empty())
        throw std::invalid_argument("A pinned tab document is required");
    } else if (!frame.at("tabId").is_null() || !frame.at("tabVersion").is_null()) {
      throw std::invalid_argument("Unbound command contains a tab");
    }
    if (jobs.contains(key)) {
      const auto& previous = jobs[key]["command"];
      auto comparable = frame;
      comparable.erase("generation");
      if (previous != comparable) throw std::invalid_argument("Attempt identity reused");
      Json frames = Json::array();
      if (jobs[key].contains("event")) {
        auto event = jobs[key]["event"];
        event["generation"] = generation;
        frames.push_back(event);
      }
      return {{"kind", "duplicate"}, {"frames", frames}};
    }
    if (jobs.size() >= 8192) throw std::runtime_error("Journal capacity reached");
    auto command = frame;
    command.erase("generation");
    jobs[key] = {{"command", command}, {"terminal", false}, {"acked", false}};
    auto accepted = Event(command, "accepted");
    accepted["generation"] = generation;
    return {{"kind", "command"}, {"command", frame}, {"frames", Json::array({accepted})}};
  }

  Json Complete(const Json& result) {
    const auto key = Key(result);
    const auto state = Text(result, "state");
    if (!Terminal(state) || !journal["jobs"].contains(key))
      throw std::invalid_argument("Unknown terminal result");
    auto& job = journal["jobs"][key];
    if (job.value("terminal", false)) return {{"kind", "ignored"}};
    auto event = Event(job["command"], state);
    if (result.contains("output")) {
      if (!result["output"].is_object() || result["output"].dump().size() > kMaxOutput)
        throw std::invalid_argument("Result too large");
      event["output"] = result["output"];
    }
    if (result.contains("error")) event["error"] = Text(result, "error").substr(0, 2000);
    job["event"] = event;
    job["terminal"] = true;
    event["generation"] = generation;
    return {{"kind", "terminal"}, {"frames", Json::array({event})}};
  }
};

extern "C" {
KelpieConnectRef kelpie_connect_create(const char* saved, const char* owner) {
  try {
    if (!owner || !*owner) return nullptr;
    auto client = std::make_unique<KelpieConnect>();
    if (saved && *saved) {
      if (std::strlen(saved) > kMaxJournal) return nullptr;
      const auto value = Json::parse(saved);
      if (value.at("version") != 1 || !value.at("jobs").is_object()) return nullptr;
      if (Text(value, "owner") == owner) client->journal = value;
    }
    client->journal["owner"] = owner;
    for (auto& job : client->journal["jobs"]) {
      Key(job.at("command"));
      if (!job.value("terminal", false)) {
        job["event"] = Event(job["command"], "failed");
        job["event"]["error"] = "UNKNOWN_EFFECTS: interrupted action requires page reconciliation";
        job["terminal"] = true;
      }
    }
    return client.release();
  } catch (...) { return nullptr; }
}
void kelpie_connect_destroy(KelpieConnectRef client) { delete client; }
char* kelpie_connect_execute(KelpieConnectRef client, const char* operation, const char* input) {
  try {
    if (!client || !operation || !input || std::strlen(input) > kMaxFrame) return nullptr;
    const auto body = Json::parse(input);
    const auto before = client->journal;
    Json decision;
    try {
      const std::string op(operation);
      if (op == "receive") decision = client->Receive(body);
      else if (op == "complete") decision = client->Complete(body);
      else if (op == "replay") decision = {{"kind", "replay"}, {"frames", client->Frames(Text(body, "generation"))}};
      else throw std::invalid_argument("Unknown operation");
      if (client->journal.dump().size() > kMaxJournal) throw std::runtime_error("Journal capacity reached");
    } catch (...) { client->journal = before; throw; }
    const auto raw = Json({{"decision", decision}, {"state", client->journal}}).dump();
    auto* result = static_cast<char*>(std::malloc(raw.size() + 1));
    if (!result) return nullptr;
    std::memcpy(result, raw.c_str(), raw.size() + 1);
    return result;
  } catch (...) { return nullptr; }
}
void kelpie_connect_free(char* json) { std::free(json); }
}
