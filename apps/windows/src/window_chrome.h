#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace kelpie::windows {

class WindowChrome {
 public:
  void Attach(HWND window, HINSTANCE instance);
  void Draw(HDC device_context) const;
  bool DrawControl(const DRAWITEMSTRUCT& item) const;
  bool EraseBackground(HDC device_context) const;
  LRESULT HitTest(WPARAM wparam, LPARAM lparam) const;
  int Inset() const;
  void LayoutControls();
  void SetActive(bool active);
  void TrackMouse(POINT point);
  void TrackMouseLeave();
  int TitleBarHeight() const;
  void UpdateDwmFrame();

 private:
  static LRESULT CALLBACK ControlProc(HWND hwnd, UINT message, WPARAM wparam,
                                      LPARAM lparam, UINT_PTR subclass_id,
                                      DWORD_PTR reference_data);
  bool IsPointInControls(POINT point) const;
  int Scale(int value) const;
  void SetControlsHovered(bool hovered);

  HWND window_ = nullptr;
  HWND close_button_ = nullptr;
  HWND minimize_button_ = nullptr;
  HWND maximize_button_ = nullptr;
  bool active_ = true;
  bool controls_hovered_ = false;
};

}  // namespace kelpie::windows
