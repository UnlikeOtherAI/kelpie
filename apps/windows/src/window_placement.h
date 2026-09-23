#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <nlohmann/json.hpp>

#include <optional>
#include <vector>

namespace kelpie::windows {

// The shell window's restored (un-maximized) frame in screen coordinates, plus
// whether it was maximized. Persisted in the profile's settings.json so the
// next launch reopens at the same size and, when it still fits, place.
struct WindowPlacement {
  RECT frame{};
  bool maximized = false;
};

std::optional<WindowPlacement> ParseWindowPlacement(const nlohmann::json& value);
nlohmann::json SerializeWindowPlacement(const WindowPlacement& placement);

// Mirrors macOS ViewportState.windowFrameIsUsable: a saved position is only
// restored when enough of the window lands on a monitor that still exists.
bool WindowFrameIsUsable(const RECT& frame, const std::vector<RECT>& work_areas);

std::vector<RECT> MonitorWorkAreas();
std::optional<WindowPlacement> CaptureWindowPlacement(HWND window);

}  // namespace kelpie::windows
