#include "session_snapshot.h"

#include <cstdint>
#include <limits>
#include <string>
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
  bad = valid; bad["nextTabId"] = -9; invalid.push_back(bad);
  bad = valid; bad["version"] = -1; invalid.push_back(bad);
  bad = valid; bad["nextTabId"] = std::numeric_limits<std::uint64_t>::max(); invalid.push_back(bad);
  bad = valid; bad["nextTabId"] = 9.5; invalid.push_back(bad);
  bad = valid; bad["nextTabId"] = "9"; invalid.push_back(bad);
  bad = valid; bad["tabs"].push_back(valid["tabs"][0]); invalid.push_back(bad);
  bad = valid; bad["tabs"][0]["id"] = "tab-02"; invalid.push_back(bad);
  bad = valid; bad["tabs"][0]["id"] = "tab-18446744073709551616"; invalid.push_back(bad);
  bad = valid; bad["tabs"][0]["url"] = "not-a-url"; invalid.push_back(bad);
  bad = valid; bad["tabs"][1]["active"] = true; invalid.push_back(bad);
  // A snapshot naming a partition the engine would reject is corrupt. Dropping
  // the field instead would restore an isolated tab into the shared store.
  for (const char* rejected : {"has space", "default", "..", "ephemeral-1", "a/b", ""}) {
    bad = valid; bad["tabs"][0]["partition"] = rejected; invalid.push_back(bad);
  }
  bad = valid; bad["tabs"][0]["partition"] = 7; invalid.push_back(bad);
  bad = valid; bad["tabs"][0]["name"] = 7; invalid.push_back(bad);
  bad = valid; bad["tabs"][0]["name"] = std::string(201, 'x'); invalid.push_back(bad);
  bad = valid; bad["tabs"][0]["persistent"] = "yes"; invalid.push_back(bad);
  // `persistent` without `partition` describes nothing.
  bad = valid; bad["tabs"][0]["persistent"] = false; invalid.push_back(bad);
  for (const auto& value : invalid) if (!UnchangedAfterInvalid(value)) return 3;

  // A start page tab must survive a restart: `kelpie://` is Kelpie's own
  // first-party scheme, not an unknown one to be discarded.
  auto start_page = valid;
  start_page["tabs"][0]["url"] = "kelpie://start";
  SessionSnapshot restored_start;
  if (!ParseSessionSnapshot(start_page, &restored_start) ||
      restored_start.tabs.front().url != "kelpie://start") return 5;
  auto other_scheme = valid;
  other_scheme["tabs"][0]["url"] = "javascript:alert(1)";
  if (!UnchangedAfterInvalid(other_scheme)) return 6;
  auto partitioned = valid;
  partitioned["tabs"][0]["partition"] = "sam.eng-lead";
  partitioned["tabs"][0]["persistent"] = false;
  partitioned["tabs"][0]["name"] = "Sam";
  partitioned["tabs"][1]["partition"] = "morgan.product";
  SessionSnapshot restored;
  if (!ParseSessionSnapshot(partitioned, &restored)) return 7;
  if (!restored.tabs[0].partition || *restored.tabs[0].partition != "sam.eng-lead") return 8;
  if (restored.tabs[0].persistent) return 9;
  if (!restored.tabs[0].name || *restored.tabs[0].name != "Sam") return 10;
  // Persistence defaults to true when the snapshot only names a partition.
  if (!restored.tabs[1].persistent || restored.tabs[1].name) return 11;
  // An ordinary tab keeps exactly the object it always had.
  const auto plain = SerializeSessionSnapshot(SessionSnapshot{1, 3, {{"tab-2", "https://a.test", true}}});
  if (plain["tabs"][0].contains("partition") || plain["tabs"][0].contains("name") ||
      plain["tabs"][0].contains("persistent")) return 12;
  SessionSnapshot partition_round_trip;
  if (!ParseSessionSnapshot(SerializeSessionSnapshot(restored), &partition_round_trip)) return 13;
  if (partition_round_trip.tabs[0].partition != restored.tabs[0].partition ||
      partition_round_trip.tabs[0].persistent != restored.tabs[0].persistent ||
      partition_round_trip.tabs[0].name != restored.tabs[0].name) return 14;

  const auto serialized = SerializeSessionSnapshot(output);
  SessionSnapshot round_trip;
  if (!ParseSessionSnapshot(serialized, &round_trip) || round_trip.next_tab_id != output.next_tab_id ||
      round_trip.tabs.size() != output.tabs.size()) return 4;
  return 0;
}
