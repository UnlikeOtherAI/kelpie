#include "session_snapshot.h"
#include <iostream>
using namespace kelpie::windows;
int main(){
 SessionSnapshot out;
 if(ParseSessionSnapshot({{"version",1},{"epoch",2},{"nextTabId",9},{"tabs",{{{"id","tab-2"},{"url","https://a"},{"active",true}},{{"id","broken"},{"url","x"}}}}},&out)==false||out.tabs.size()!=1||out.next_tab_id!=9) return 1;
 if(ParseSessionSnapshot({{"version",1},{"nextTabId",0},{"tabs",nlohmann::json::array()}},&out)) return 2;
 const auto round=SerializeSessionSnapshot(out); if(round.value("version",0)!=1) return 3;
 return 0;
}
