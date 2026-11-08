#pragma once

#include <string>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace kelpie::windows {

class ToastView {
 public:
  bool Create(HWND parent, HINSTANCE instance);
  void Resize(const RECT& parent_bounds);
  void ShowMessage(const std::wstring& message);
  void Hide();

 private:
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  void Paint(HDC device_context) const;

  HWND hwnd_ = nullptr;
  std::wstring message_;
};

}  // namespace kelpie::windows
