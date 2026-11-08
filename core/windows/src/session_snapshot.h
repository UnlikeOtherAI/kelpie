#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

namespace kelpie::windows {

struct SessionTab {
  std::string id;
  std::string url;
  bool active = false;
  // Caller-supplied label, shown in the tab strip in place of the page title.
  std::optional<std::string> name;
  // Storage partition the tab was bound to. Absent means the default shared
  // store. Restoring rebinds the tab to the same partition, which is what
  // makes an isolated identity outlive a restart.
  std::optional<std::string> partition;
  // Only meaningful with `partition`. A non-persistent partition has no
  // on-disk store, so its tab restores into a fresh, empty one.
  bool persistent = true;
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
