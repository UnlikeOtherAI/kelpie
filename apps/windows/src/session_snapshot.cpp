#include "session_snapshot.h"
#include <charconv>
namespace kelpie::windows {
bool ParseSessionSnapshot(const nlohmann::json& value, SessionSnapshot* output) {
 if (!output || !value.is_object() || value.value("version",0)!=1 || !value.contains("tabs") || !value["tabs"].is_array()) return false;
 SessionSnapshot next; next.epoch=value.value("epoch",std::uint64_t{0}); next.next_tab_id=value.value("nextTabId",std::uint64_t{1});
 if(next.next_tab_id<1) return false; bool active=false;
 for(const auto& item:value["tabs"]){ if(!item.is_object()) continue; SessionTab tab{item.value("id", ""),item.value("url", ""),item.value("active",false)}; std::uint64_t id=0; const auto parsed=std::from_chars(tab.id.data()+4,tab.id.data()+tab.id.size(),id); if(tab.id.rfind("tab-",0)!=0 || tab.url.empty() || parsed.ec!=std::errc{}) continue; if(tab.active){if(active) continue;active=true;} next.tabs.push_back(std::move(tab)); }
 if(next.tabs.empty()) return false; if(!active) next.tabs.front().active=true; *output=std::move(next); return true;
}
nlohmann::json SerializeSessionSnapshot(const SessionSnapshot& snapshot){nlohmann::json tabs=nlohmann::json::array();for(const auto& tab:snapshot.tabs)tabs.push_back({{"id",tab.id},{"url",tab.url},{"active",tab.active}});return {{"version",1},{"epoch",snapshot.epoch},{"nextTabId",snapshot.next_tab_id},{"tabs",tabs}};}
}
