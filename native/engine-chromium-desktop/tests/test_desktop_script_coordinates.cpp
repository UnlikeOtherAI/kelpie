#include "desktop_script_coordinates.h"
#include <cassert>
#include <limits>

int main(){
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
