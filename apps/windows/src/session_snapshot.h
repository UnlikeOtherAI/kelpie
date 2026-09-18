#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

namespace kelpie::windows {

struct SessionTab {
  std::string id;
  std::string url;
  bool active = false;
};

// This is the durable model owned by the Windows profile. next_tab_id is the
// engine allocator high-water mark, not a value reconstructed from open tabs.
struct SessionSnapshot {
  std::uint64_t epoch = 0;
  std::uint64_t next_tab_id = 1;
  std::vector<SessionTab> tabs;
};

bool ParseSessionSnapshot(const nlohmann::json& value, SessionSnapshot* output);
nlohmann::json SerializeSessionSnapshot(const SessionSnapshot& snapshot);

}  // namespace kelpie::windows
