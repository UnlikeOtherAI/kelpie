#include "window_placement.h"

#include <cassert>

using kelpie::windows::ParseWindowPlacement;
using kelpie::windows::SerializeWindowPlacement;
using kelpie::windows::WindowFrameIsUsable;
using kelpie::windows::WindowPlacement;

namespace {

bool SameRect(const RECT& a, const RECT& b) {
  return a.left == b.left && a.top == b.top && a.right == b.right && a.bottom == b.bottom;
}

// What is saved on close must come back unchanged on the next launch.
void RoundTripsThroughJson() {
  WindowPlacement placement;
  placement.frame = RECT{-1600, 40, -400, 840};
  placement.maximized = true;
  const auto parsed = ParseWindowPlacement(SerializeWindowPlacement(placement));
  assert(parsed.has_value());
  assert(SameRect(parsed->frame, placement.frame));
  assert(parsed->maximized);
}

// A missing, partial or hand-edited entry is ignored rather than trusted.
void RejectsMalformedEntries() {
  assert(!ParseWindowPlacement(nlohmann::json()).has_value());
  assert(!ParseWindowPlacement({{"x", 10}, {"y", 10}, {"width", 900}}).has_value());
  assert(!ParseWindowPlacement({{"x", "10"}, {"y", 10}, {"width", 900}, {"height", 700}}).has_value());
  // Below the --width/--height minimums: a collapsed window must not stick.
  assert(!ParseWindowPlacement({{"x", 0}, {"y", 0}, {"width", 100}, {"height", 700}}).has_value());
  assert(!ParseWindowPlacement({{"x", 0}, {"y", 0}, {"width", 900}, {"height", 20}}).has_value());
  const auto legacy = ParseWindowPlacement({{"x", 0}, {"y", 0}, {"width", 900}, {"height", 700}});
  assert(legacy.has_value() && !legacy->maximized);
}

// A position is reused only while enough of the frame sits on a live monitor.
void RequiresTheFrameOnAConnectedMonitor() {
  const std::vector<RECT> single{RECT{0, 0, 1920, 1040}};
  assert(WindowFrameIsUsable(RECT{100, 100, 1100, 800}, single));
  // Saved on a second monitor that has since been unplugged.
  assert(!WindowFrameIsUsable(RECT{2000, 100, 3000, 800}, single));
  // Hanging off the right edge with only a sliver still on screen.
  assert(!WindowFrameIsUsable(RECT{1850, 100, 2850, 800}, single));
  // Mostly off-screen but with a usable title-bar strip left.
  assert(WindowFrameIsUsable(RECT{1700, 1000, 2700, 1700}, single));
  // Monitors to the left of the primary have negative coordinates.
  const std::vector<RECT> dual{RECT{0, 0, 1920, 1040}, RECT{-1920, 0, 0, 1040}};
  assert(WindowFrameIsUsable(RECT{-1600, 40, -400, 840}, dual));
  assert(!WindowFrameIsUsable(RECT{100, 100, 1100, 800}, {}));
}

}  // namespace

int main() {
  RoundTripsThroughJson();
  RejectsMalformedEntries();
  RequiresTheFrameOnAConnectedMonitor();
  return 0;
}
