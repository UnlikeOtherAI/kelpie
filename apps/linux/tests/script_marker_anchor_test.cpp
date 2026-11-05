#include "../src/script_marker_anchor.h"
#include <cassert>
using namespace kelpie::linuxapp;
int main() {
  ScriptMarkerAnchor anchor;
  const ScriptMarkerGeometry base{5,40,1200,800,1,1200,800};
  assert(!anchor.Matches("run/tab/document/action",base));
  anchor.Observe("run/tab/document/action",base);
  assert(anchor.Matches("run/tab/document/action",base));
  assert(!anchor.Matches("other-run/tab/document/action",base));
  auto moved=base; ++moved.x; assert(!anchor.Matches("run/tab/document/action",moved));
  moved=base; ++moved.y; assert(!anchor.Matches("run/tab/document/action",moved));
  moved=base; ++moved.width; assert(!anchor.Matches("run/tab/document/action",moved));
  moved=base; ++moved.height; assert(!anchor.Matches("run/tab/document/action",moved));
  moved=base; ++moved.scale; assert(!anchor.Matches("run/tab/document/action",moved));
  moved=base; ++moved.frame_width; assert(!anchor.Matches("run/tab/document/action",moved));
  moved=base; ++moved.frame_height; assert(!anchor.Matches("run/tab/document/action",moved));
  anchor.Clear(); assert(!anchor.Matches("run/tab/document/action",base));
}
