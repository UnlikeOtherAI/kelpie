#include "script_frame_compositor.h"
#include <cassert>
#include <algorithm>
using kelpie::windows::ScriptMediaFrame;
using kelpie::windows::DrawScriptOverlay;

ScriptMediaFrame White() {
  ScriptMediaFrame frame; frame.width=200; frame.height=200; frame.stride=800;
  frame.bgra.assign(160000,255); return frame;
}
int main() {
  const nlohmann::json shown={{"viewportWidth",100},{"viewportHeight",100},{"elapsedMs",100},
    {"marker",{{"x",25},{"y",25},{"radius",10},{"durationMs",700},{"startedMs",100},
      {"color","#FF0000"},{"wobble",false},{"fade",true}}}};
  auto frame=White(); DrawScriptOverlay(frame,shown);
  const auto center=50*frame.stride+50*4;
  assert(frame.bgra[center]<100 && frame.bgra[center+1]<100 && frame.bgra[center+2]==255 && frame.bgra[center+3]==255);
  const auto outside=10*frame.stride+10*4;
  assert(frame.bgra[outside]==255 && frame.bgra[outside+1]==255);
  auto faded=White(); auto end=shown; end["elapsedMs"]=800; DrawScriptOverlay(faded,end);
  assert(std::all_of(faded.bgra.begin(),faded.bgra.end(),[](unsigned char value){return value==255;}));
  auto transparent=White(); transparent.bgra.assign(160000,0); DrawScriptOverlay(transparent,shown);
  assert(transparent.bgra[center+3]>0 && transparent.bgra[center+3]<255);
  assert(transparent.bgra[outside+3]==0);
  auto pointer=White(); DrawScriptOverlay(pointer,{{"viewportWidth",100},{"viewportHeight",100},{"pointer",{{"x",20},{"y",20}}}});
  assert(pointer.bgra!=White().bgra);
}
