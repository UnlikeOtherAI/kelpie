#include "session_snapshot.h"
using namespace kelpie::windows;
#include <vector>
int main() {
  SessionSnapshot out;
  const nlohmann::json valid={{"version",1},{"epoch",2},{"nextTabId",9},{"tabs",{{{"id","tab-2"},{"url","https://a"},{"active",true}},{{"id","tab-8"},{"url","https://b"},{"active",false}}}}};
  if(!ParseSessionSnapshot(valid,&out)||out.tabs.size()!=2||out.next_tab_id!=9) return 1;
  const std::vector<nlohmann::json> invalids = {nlohmann::json{{"version",1},{"epoch","bad"},{"nextTabId",9},{"tabs",valid["tabs"]}}, nlohmann::json{{"version",1},{"epoch",2},{"nextTabId",2},{"tabs",valid["tabs"]}}, nlohmann::json{{"version",1},{"epoch",2},{"nextTabId",9},{"tabs",{{{"id","tab-2"},{"url","x"},{"active",true}},{{"id","tab-2"},{"url","y"},{"active",false}}}}}}};
  for (const auto& invalid : invalids) if(ParseSessionSnapshot(invalid,&out)) return 2;
  const auto round=SerializeSessionSnapshot(out); if(round.value("version",0)!=1) return 3;
  return 0;
}
