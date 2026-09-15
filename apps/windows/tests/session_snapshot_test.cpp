#include "session_snapshot.h"

#include <cstdint>
#include <limits>
#include <vector>

using namespace kelpie::windows;

namespace {

nlohmann::json Valid() {
  return {{"version", 1}, {"epoch", 2}, {"nextTabId", 9},
          {"tabs", nlohmann::json::array({
              {{"id", "tab-2"}, {"url", "https://a.test"}, {"active", true}},
              {{"id", "tab-8"}, {"url", "https://a.test"}, {"active", false}},
          })}};
}

bool UnchangedAfterInvalid(const nlohmann::json& invalid) {
  SessionSnapshot output{17, 22, {{"tab-21", "https://unchanged.test", true}}};
  const SessionSnapshot before = output;
  return !ParseSessionSnapshot(invalid, &output) && output.epoch == before.epoch &&
      output.next_tab_id == before.next_tab_id && output.tabs.front().id == before.tabs.front().id;
}

}  // namespace

int main() {
  SessionSnapshot output;
  const auto valid = Valid();
  if (!ParseSessionSnapshot(valid, &output) || output.tabs.size() != 2 || output.next_tab_id != 9 ||
      !output.tabs.front().active || output.tabs.front().url != output.tabs.back().url) return 1;

  auto missing_active = valid;
  missing_active["tabs"][0]["active"] = false;
  if (!ParseSessionSnapshot(missing_active, &output) || !output.tabs.front().active) return 2;

  std::vector<nlohmann::json> invalid;
  auto bad = valid; bad["epoch"] = -1; invalid.push_back(bad);
  bad = valid; bad["nextTabId"] = 0; invalid.push_back(bad);
  bad = valid; bad["nextTabId"] = std::numeric_limits<std::uint64_t>::max(); invalid.push_back(bad);
  bad = valid; bad["nextTabId"] = 9.5; invalid.push_back(bad);
  bad = valid; bad["nextTabId"] = "9"; invalid.push_back(bad);
  bad = valid; bad["tabs"].push_back(valid["tabs"][0]); invalid.push_back(bad);
  bad = valid; bad["tabs"][0]["id"] = "tab-02"; invalid.push_back(bad);
  bad = valid; bad["tabs"][0]["id"] = "tab-18446744073709551616"; invalid.push_back(bad);
  bad = valid; bad["tabs"][0]["url"] = "not-a-url"; invalid.push_back(bad);
  bad = valid; bad["tabs"][1]["active"] = true; invalid.push_back(bad);
  for (const auto& value : invalid) if (!UnchangedAfterInvalid(value)) return 3;

  const auto serialized = SerializeSessionSnapshot(output);
  SessionSnapshot round_trip;
  if (!ParseSessionSnapshot(serialized, &round_trip) || round_trip.next_tab_id != output.next_tab_id ||
      round_trip.tabs.size() != output.tabs.size()) return 4;
  return 0;
}
