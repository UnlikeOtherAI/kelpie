#include "../src/script_marker_anchor.h"
#include <cassert>
using namespace kelpie::linuxapp;
int main() {
  ScriptMarkerAnchor anchor;
  const ScriptMarkerGeometry base{5,40,1200,800,1,1200,800};
  assert(!anchor.Matches(2,"run/tab/document/action",base));
  anchor.Observe(2,"run/tab/document/action",base);
  assert(anchor.Matches(2,"run/tab/document/action",base));
  assert(!anchor.Matches(2,"other-run/tab/document/action",base));
  auto moved=base; ++moved.x; assert(!anchor.Matches(2,"run/tab/document/action",moved));
  moved=base; ++moved.y; assert(!anchor.Matches(2,"run/tab/document/action",moved));
  moved=base; ++moved.width; assert(!anchor.Matches(2,"run/tab/document/action",moved));
  moved=base; ++moved.height; assert(!anchor.Matches(2,"run/tab/document/action",moved));
  moved=base; ++moved.scale; assert(!anchor.Matches(2,"run/tab/document/action",moved));
  moved=base; ++moved.frame_width; assert(!anchor.Matches(2,"run/tab/document/action",moved));
  moved=base; ++moved.frame_height; assert(!anchor.Matches(2,"run/tab/document/action",moved));
  moved=base; ++moved.width;
  anchor.Observe(2,"run/tab/document/action",moved);
  anchor.Observe(2,"run/tab/document/action",base);
  assert(!anchor.Matches(2,"run/tab/document/action",base));
  anchor.Observe(2,"new-run/tab/document/action",base);
  assert(anchor.Matches(2,"new-run/tab/document/action",base));
  anchor.Invalidate(2,"new-run/tab/document/action");
  anchor.Observe(2,"new-run/tab/document/action",base);
  assert(!anchor.Matches(2,"new-run/tab/document/action",base));
  anchor.Observe(2,"next-run/tab/document/action",base);
  assert(anchor.Matches(2,"next-run/tab/document/action",base));
  anchor.Observe(1,"old-run/tab/document/action",base);
  assert(anchor.Matches(2,"next-run/tab/document/action",base));
  assert(!anchor.Matches(1,"next-run/tab/document/action",base));
  anchor.Clear(); assert(!anchor.Matches(2,"next-run/tab/document/action",base));
}
