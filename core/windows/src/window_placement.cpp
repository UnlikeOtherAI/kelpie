#include "window_placement.h"

#include <algorithm>

namespace kelpie::windows {
namespace {

// The same bounds main.cpp accepts for --width and --height.
constexpr int kMinWidth = 320;
constexpr int kMinHeight = 240;
constexpr int kMaxEdge = 16384;
// macOS requires this much of the frame on a screen before it trusts a saved
// position; anything less leaves the title bar unreachable.
constexpr LONG kMinVisibleWidth = 120;
constexpr LONG kMinVisibleHeight = 40;

bool HasUsableSize(const RECT& frame) {
  const LONG width = frame.right - frame.left;
  const LONG height = frame.bottom - frame.top;
  return width >= kMinWidth && width <= kMaxEdge && height >= kMinHeight && height <= kMaxEdge;
}

BOOL CALLBACK CollectWorkArea(HMONITOR monitor, HDC, LPRECT, LPARAM context) {
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  if (GetMonitorInfoW(monitor, &info)) {
    reinterpret_cast<std::vector<RECT>*>(context)->push_back(info.rcWork);
  }
  return TRUE;
}

}  // namespace

std::optional<WindowPlacement> ParseWindowPlacement(const nlohmann::json& value) {
  if (!value.is_object()) return std::nullopt;
  for (const char* key : {"x", "y", "width", "height"}) {
    if (!value.contains(key) || !value[key].is_number_integer()) return std::nullopt;
  }
  WindowPlacement placement;
  placement.frame.left = value["x"].get<LONG>();
  placement.frame.top = value["y"].get<LONG>();
  placement.frame.right = placement.frame.left + value["width"].get<LONG>();
  placement.frame.bottom = placement.frame.top + value["height"].get<LONG>();
  placement.maximized = value.value("maximized", false);
  if (!HasUsableSize(placement.frame)) return std::nullopt;
  return placement;
}

nlohmann::json SerializeWindowPlacement(const WindowPlacement& placement) {
  return {{"x", placement.frame.left},
          {"y", placement.frame.top},
          {"width", placement.frame.right - placement.frame.left},
          {"height", placement.frame.bottom - placement.frame.top},
          {"maximized", placement.maximized}};
}

bool WindowFrameIsUsable(const RECT& frame, const std::vector<RECT>& work_areas) {
  return std::any_of(work_areas.begin(), work_areas.end(), [&frame](const RECT& area) {
    RECT overlap{};
    return IntersectRect(&overlap, &frame, &area) &&
        overlap.right - overlap.left >= kMinVisibleWidth &&
        overlap.bottom - overlap.top >= kMinVisibleHeight;
  });
}

std::vector<RECT> MonitorWorkAreas() {
  std::vector<RECT> areas;
  EnumDisplayMonitors(nullptr, nullptr, &CollectWorkArea, reinterpret_cast<LPARAM>(&areas));
  return areas;
}

std::optional<WindowPlacement> CaptureWindowPlacement(HWND window) {
  WINDOWPLACEMENT native{};
  native.length = sizeof(native);
  if (window == nullptr || !GetWindowPlacement(window, &native)) return std::nullopt;
  WindowPlacement placement;
  placement.maximized = native.showCmd == SW_SHOWMAXIMIZED;
  // rcNormalPosition is the frame the window returns to from maximized or
  // minimized, but in workspace coordinates: offset by the taskbar when it
  // sits on the monitor's top or left edge. Shift it back to screen space so
  // the saved frame means the same thing as CreateWindowExW's x and y.
  placement.frame = native.rcNormalPosition;
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  if (GetMonitorInfoW(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST), &info)) {
    OffsetRect(&placement.frame, info.rcWork.left - info.rcMonitor.left,
               info.rcWork.top - info.rcMonitor.top);
  }
  if (!HasUsableSize(placement.frame)) return std::nullopt;
  return placement;
}

}  // namespace kelpie::windows
