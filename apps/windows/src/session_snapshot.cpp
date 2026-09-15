#include "session_snapshot.h"
#include <charconv>
#include <unordered_set>
namespace kelpie::windows {
namespace {
bool TabNumber(const std::string& id, std::uint64_t* number) {
  if (!number || id.size() <= 4 || id.rfind("tab-", 0) != 0) return false;
  const auto parsed = std::from_chars(id.data() + 4, id.data() + id.size(), *number);
  return parsed.ec == std::errc{} && parsed.ptr == id.data() + id.size() && *number > 0;
}
}
bool ParseSessionSnapshot(const nlohmann::json& value, SessionSnapshot* output) {
  if (!output || !value.is_object() || !value.contains("version") || !value["version"].is_number_integer() ||
      value["version"] != 1 || !value.contains("epoch") || !value["epoch"].is_number_integer() ||
      !value.contains("nextTabId") || !value["nextTabId"].is_number_integer() ||
      !value.contains("tabs") || !value["tabs"].is_array()) return false;
  SessionSnapshot next; next.epoch=value["epoch"].get<std::uint64_t>(); next.next_tab_id=value["nextTabId"].get<std::uint64_t>();
  if (next.next_tab_id < 1) return false;
  std::unordered_set<std::string> ids; bool active=false; std::uint64_t highest=0;
  for (const auto& item : value["tabs"]) {
    if (!item.is_object() || !item.contains("id") || !item["id"].is_string() || !item.contains("url") || !item["url"].is_string() ||
        !item.contains("active") || !item["active"].is_boolean()) return false;
    SessionTab tab{item["id"].get<std::string>(), item["url"].get<std::string>(), item["active"].get<bool>()}; std::uint64_t number=0;
    if (!TabNumber(tab.id,&number) || tab.url.empty() || !ids.insert(tab.id).second || (tab.active && active)) return false;
    highest=std::max(highest,number); active|=tab.active; next.tabs.push_back(std::move(tab));
  }
  if (next.tabs.empty() || next.next_tab_id <= highest) return false;
  if (!active) next.tabs.front().active=true;
  *output=std::move(next); return true;
}
nlohmann::json SerializeSessionSnapshot(const SessionSnapshot& snapshot) {
 nlohmann::json tabs=nlohmann::json::array(); for(const auto& tab:snapshot.tabs) tabs.push_back({{"id",tab.id},{"url",tab.url},{"active",tab.active}});
 return {{"version",1},{"epoch",snapshot.epoch},{"nextTabId",snapshot.next_tab_id},{"tabs",tabs}};
}
}
