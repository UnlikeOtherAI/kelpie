#include "../src/script_terminal_frame.h"
#include <cassert>
using namespace kelpie::linuxapp;
int main() {
  using nlohmann::json;
  json shown={{"runId","run"},{"tabId","tab"},{"generation",7},{"documentVersion","doc"},
    {"marker",{{"actionIndex",3},{"startedMs",100},{"durationMs",700}}},
    {"viewportWidth",640},{"viewportHeight",480},{"visualViewport",{{"scale",1}}}};
  const auto before=TerminalFrameProof(shown,799),clear=TerminalFrameProof(shown,800);
  assert(!MatchingTerminalFrameProof(before,clear));
  assert(MatchingTerminalFrameProof(clear,TerminalFrameProof(shown,900)));
  auto changed=shown;changed["documentVersion"]="other";
  assert(!MatchingTerminalFrameProof(clear,TerminalFrameProof(changed,900)));
  changed=shown;changed["marker"]["actionIndex"]=4;
  assert(!MatchingTerminalFrameProof(clear,TerminalFrameProof(changed,900)));
  changed=shown;changed["visualViewport"]["scale"]=2;
  assert(!MatchingTerminalFrameProof(clear,TerminalFrameProof(changed,900)));
  changed=shown;changed.erase("marker");
  assert(!MatchingTerminalFrameProof(clear,TerminalFrameProof(changed,900)));
}
