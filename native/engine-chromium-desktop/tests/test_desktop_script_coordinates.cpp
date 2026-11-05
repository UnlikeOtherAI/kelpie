#include "desktop_script_coordinates.h"
#include <cassert>
#include <limits>

int main(){
  assert(!kelpie::ScriptTargetPostMutationExplicit({{"ok",true},{"sensitive",false}}));
  assert(!kelpie::ScriptTargetPostMutationExplicit({{"ok",true},{"sensitive",false},{"sensitivityKnown","false"}}));
  assert(kelpie::ScriptTargetPostMutationExplicit({{"ok",true},{"sensitive",false},{"sensitivityKnown",false}}));
  assert(kelpie::ScriptTargetPostMutationExplicit({{"ok",true},{"sensitive",true},{"sensitivityKnown",true}}));
  assert(kelpie::ScriptTargetInspectionUncertain(nullptr));
  assert(kelpie::ScriptTargetInspectionUncertain({{"ok",false},{"sensitive",false},{"sensitivityKnown",false},{"error","STALE_TARGET"}}));
  assert(kelpie::ScriptTargetInspectionUncertain({{"ok",false},{"sensitive",false}}));
  assert(kelpie::ScriptTargetInspectionUncertain({{"ok",false}}));
  assert(!kelpie::ScriptTargetInspectionUncertain({{"ok",false},{"sensitive",true},{"error","TARGET_MOVED"}}));
  assert(!kelpie::ScriptTargetInspectionUncertain({{"ok",false},{"sensitive",false},{"sensitivityKnown",true},{"error","TARGET_NOT_FOUND"}}));
  nlohmann::json viewport={{"width",1042},{"height",662},{"visualViewport",{
    {"offsetLeft",0},{"offsetTop",0},{"width",1042},{"height",662},{"scale",1}}}};
  auto gutter=viewport;gutter["visualViewport"]["width"]=1027;
  assert(kelpie::ScriptCaptureViewportCompatible(viewport,gutter,true));
  auto pan=gutter;pan["visualViewport"]["offsetLeft"]=1;
  assert(!kelpie::ScriptCaptureViewportCompatible(gutter,pan,true));
  assert(kelpie::ScriptCaptureViewportCompatible(gutter,pan,false));
  auto resized=gutter;resized["width"]=1043;
  assert(!kelpie::ScriptCaptureViewportCompatible(gutter,resized,false));
  auto zoom=gutter;zoom["visualViewport"]["scale"]=2;
  assert(!kelpie::ScriptCaptureViewportCompatible(gutter,zoom,true));
  nlohmann::json target={{"x",375},{"y",120},{"visualViewport",{
    {"offsetLeft",0},{"offsetTop",0},{"width",400},{"height",300},{"scale",2}}}};
  auto point=kelpie::ScriptTargetCdpPoint(target);
  assert(point&&point->x==375&&point->y==120);
  target["x"]=402;target["visualViewport"]["offsetLeft"]=54;target["visualViewport"]["offsetTop"]=43;
  point=kelpie::ScriptTargetCdpPoint(target);
  assert(point&&point->x==348&&point->y==77); // Actual trusted CDP raw-pan vector.
  target["visualViewport"]["scale"]=4;
  point=kelpie::ScriptTargetCdpPoint(target);
  assert(point&&point->x==348&&point->y==77); // Never multiply by page scale or DPR.
  target["x"]=454;
  assert(!kelpie::ScriptTargetCdpPoint(target)); // Right edge lies outside visible CSS viewport.
  target["x"]=402;target["visualViewport"]["offsetLeft"]=std::numeric_limits<double>::infinity();
  assert(!kelpie::ScriptTargetCdpPoint(target));
  target.erase("visualViewport");
  assert(!kelpie::ScriptTargetCdpPoint(target)); // Fail closed if generated metadata is missing.
}
