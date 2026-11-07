#include "maximized_frame.h"

#include <cassert>

using kelpie::windows::AutoHideEdges;
using kelpie::windows::kAutoHideRevealPx;
using kelpie::windows::MaximizedClientRect;

namespace {

bool SameRect(const RECT& a, const RECT& b) {
  return a.left == b.left && a.top == b.top && a.right == b.right && a.bottom == b.bottom;
}

// Windows maximizes a WS_THICKFRAME window to its work area inflated by the
// frame on every side; this is that rect for a given work area.
RECT MaximizedWindowFor(const RECT& work_area, SIZE frame) {
  return {work_area.left - frame.cx, work_area.top - frame.cy, work_area.right + frame.cx,
          work_area.bottom + frame.cy};
}

// The reported defect: 1920x1080 at 100% with a 48 px bottom taskbar. The
// window is 1936x1048 at (-8,-8); the client area must be the 1920x1032 work
// area, not the whole window.
void FillsTheWorkAreaAt100Percent() {
  const RECT work_area{0, 0, 1920, 1032};
  const SIZE frame{8, 8};
  const RECT client = MaximizedClientRect(MaximizedWindowFor(work_area, frame), frame, {});
  assert(SameRect(client, work_area));
}

// A secondary monitor left of the primary, at 150%: negative coordinates and
// a thicker frame change nothing about the rule.
void FillsTheWorkAreaOnAScaledSecondaryMonitor() {
  const RECT work_area{-2560, 0, 0, 1392};
  const SIZE frame{11, 11};
  const RECT client = MaximizedClientRect(MaximizedWindowFor(work_area, frame), frame, {});
  assert(SameRect(client, work_area));
}

// An auto-hide taskbar reserves no work area, so the work area is the whole
// monitor; the edge the bar hides on must stay uncovered so it can slide in.
void LeavesAnAutoHideTaskbarEdgeUncovered() {
  const RECT monitor{0, 0, 1920, 1080};
  const SIZE frame{8, 8};
  const RECT window = MaximizedWindowFor(monitor, frame);
  AutoHideEdges bottom;
  bottom.bottom = true;
  assert(SameRect(MaximizedClientRect(window, frame, bottom),
                  RECT{0, 0, 1920, 1080 - kAutoHideRevealPx}));
  AutoHideEdges left;
  left.left = true;
  assert(SameRect(MaximizedClientRect(window, frame, left),
                  RECT{kAutoHideRevealPx, 0, 1920, 1080}));
  AutoHideEdges top;
  top.top = true;
  assert(SameRect(MaximizedClientRect(window, frame, top),
                  RECT{0, kAutoHideRevealPx, 1920, 1080}));
  AutoHideEdges right;
  right.right = true;
  assert(SameRect(MaximizedClientRect(window, frame, right),
                  RECT{0, 0, 1920 - kAutoHideRevealPx, 1080}));
}

}  // namespace

int main() {
  FillsTheWorkAreaAt100Percent();
  FillsTheWorkAreaOnAScaledSecondaryMonitor();
  LeavesAnAutoHideTaskbarEdgeUncovered();
  return 0;
}
