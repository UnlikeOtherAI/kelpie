#pragma once
#include <cstdint>
#include <string>
#include <vector>
#include <nlohmann/json.hpp>
namespace kelpie::windows {
struct SessionTab { std::string id; std::string url; bool active = false; };
struct SessionSnapshot { std::uint64_t epoch = 0; std::uint64_t next_tab_id = 1; std::vector<SessionTab> tabs; };
bool ParseSessionSnapshot(const nlohmann::json&, SessionSnapshot*);
nlohmann::json SerializeSessionSnapshot(const SessionSnapshot&);
}
