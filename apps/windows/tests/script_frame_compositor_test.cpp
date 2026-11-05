#include "script_frame_compositor.h"
#include "script_capture_cadence.h"
#include <cassert>
#include <objbase.h>
#include <algorithm>
using kelpie::windows::ScriptMediaFrame;
using kelpie::windows::DrawScriptOverlay;

ScriptMediaFrame White() {
  ScriptMediaFrame frame; frame.width=200; frame.height=200; frame.stride=800;
  frame.bgra.assign(160000,255); return frame;
}
int main() {
  assert(SUCCEEDED(CoInitializeEx(nullptr,COINIT_MULTITHREADED)));
  kelpie::windows::ScriptFrameSourceSize source;
  const auto decoded=kelpie::windows::DecodeScriptFrame(
    "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAGCAYAAAD+Bd/7AAAAD0lEQVR4nGP4TwAwDAUFAPrNv0HlRvlbAAAAAElFTkSuQmCC",
    4,0,&source);
  assert(source.width==8 && source.height==6);
  assert(decoded.width==4 && decoded.height==2); // Source bounds survive scaling/even rounding.
  CoUninitialize();
  double previous=-1; int count=0;
  for(int elapsed=0;elapsed<=1000;++elapsed) {
    if(kelpie::windows::ScriptMovieFrameDue(previous,elapsed,15)) {
      if(previous>=0) assert(elapsed-previous>=1000.0/15);
      previous=elapsed; ++count;
    }
  }
  assert(count<=16 && count>=15);
  assert(!kelpie::windows::ScriptMovieFrameDue(100,120,15));
  assert(kelpie::windows::ScriptMovieFrameDue(100,167,15));
  const nlohmann::json shown={{"viewportWidth",100},{"viewportHeight",100},{"elapsedMs",100},
    {"marker",{{"x",25},{"y",25},{"radius",10},{"durationMs",700},{"startedMs",100},
      {"color","#FF0000"},{"wobble",false},{"fade",true}}}};
  auto frame=White(); DrawScriptOverlay(frame,shown);
  const auto center=50*frame.stride+50*4;
  assert(frame.bgra[center]<100 && frame.bgra[center+1]<100 && frame.bgra[center+2]==255 && frame.bgra[center+3]==255);
  auto held=White(); auto future=shown; future["marker"]["startedMs"]=300101;
  DrawScriptOverlay(held,future);
  assert(held.bgra==frame.bgra); // Evidence hold is visibly identical to progress zero.
  const auto outside=10*frame.stride+10*4;
  assert(frame.bgra[outside]==255 && frame.bgra[outside+1]==255);
  auto faded=White(); auto end=shown; end["elapsedMs"]=800; DrawScriptOverlay(faded,end);
  assert(std::all_of(faded.bgra.begin(),faded.bgra.end(),[](unsigned char value){return value==255;}));
  auto transparent=White(); transparent.bgra.assign(160000,0); DrawScriptOverlay(transparent,shown);
  assert(transparent.bgra[center+3]>0 && transparent.bgra[center+3]<255);
  assert(transparent.bgra[outside+3]==0);
  auto pointer=White(); DrawScriptOverlay(pointer,{{"viewportWidth",100},{"viewportHeight",100},{"pointer",{{"x",20},{"y",20}}}});
  assert(pointer.bgra!=White().bgra);
  auto visual=shown;
  visual["visualViewport"]={{"offsetLeft",10},{"offsetTop",5},{"width",50},{"height",50},{"scale",2}};
  auto zoomed=White();DrawScriptOverlay(zoomed,visual);
  const auto mapped=80*zoomed.stride+60*4;
  assert(zoomed.bgra[mapped]<100&&zoomed.bgra[mapped+1]<100&&zoomed.bgra[mapped+2]==255);
  const auto left=80*zoomed.stride+10*4;
  assert(zoomed.bgra[left]==255&&zoomed.bgra[left+1]==255);
  auto invalid=visual;invalid["visualViewport"]["width"]=0;
  bool refused=false;try{auto ignored=White();DrawScriptOverlay(ignored,invalid);}catch(...){refused=true;}
  assert(refused);
  nlohmann::json note={{"elapsedMs",0},{"visualViewport",visual["visualViewport"]},
    {"commentary",{{"text","Viewport note"},{"position","center"},{"startedMs",0},{"durationMs",3000}}}};
  auto note_first=White();DrawScriptOverlay(note_first,note);
  note["visualViewport"]["offsetLeft"]=30;note["visualViewport"]["offsetTop"]=25;
  auto note_panned=White();DrawScriptOverlay(note_panned,note);
  assert(note_first.bgra==note_panned.bgra);
  assert(note_first.bgra!=White().bgra);

  auto scrollbar=shown;
  scrollbar["visualViewport"]={{"offsetLeft",0},{"offsetTop",0},{"width",90},{"height",90},{"scale",1}};
  auto classic_bar=White();DrawScriptOverlay(classic_bar,scrollbar);
  assert(classic_bar.bgra==frame.bgra); // A scrollbar must not scale or drift the marker.

}
