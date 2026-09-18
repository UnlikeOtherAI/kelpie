#include "session_snapshot.h"
#include <vector>
using namespace kelpie::windows;
int main() {
  SessionSnapshot out;
  nlohmann::json valid = {{"version", 1}, {"epoch", 2}, {"nextTabId", 9}, {"tabs", nlohmann::json::array({{{"id", "tab-2"}, {"url", "https://a"}, {"active", true}}, {{"id", "tab-8"}, {"url", "https://b"}, {"active", false}}})}};
  if (!ParseSessionSnapshot(valid, &out) || out.tabs.size() != 2 || out.next_tab_id != 9) return 1;
  auto invalid = valid; invalid["epoch"] = "bad"; if (ParseSessionSnapshot(invalid, &out)) return 2;
  invalid = valid; invalid["nextTabId"] = 2; if (ParseSessionSnapshot(invalid, &out)) return 3;
  invalid = valid; invalid["tabs"].push_back(valid["tabs"][0]); if (ParseSessionSnapshot(invalid, &out)) return 4;
  // A negative count is not an unsigned one: accepting it wraps the value into
  // an enormous id rather than rejecting the corrupted file.
  invalid = valid; invalid["epoch"] = -1; if (ParseSessionSnapshot(invalid, &out)) return 6;
  invalid = valid; invalid["nextTabId"] = -9; if (ParseSessionSnapshot(invalid, &out)) return 7;
  invalid = valid; invalid["version"] = -1; if (ParseSessionSnapshot(invalid, &out)) return 8;
  return SerializeSessionSnapshot(out).value("version", 0) == 1 ? 0 : 5;
}
