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

class NetworkInspector {
 public:
  bool EnsureCreated(HINSTANCE instance, HWND owner);
  void ToggleVisible();
  void UpdateFromJson(const std::string& network_json);

 private:
  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  LRESULT HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);
  void CreateControls();
  void Resize();
  void PopulateFilters() const;
  void ApplyFilter();

  HINSTANCE instance_ = nullptr;
  HWND owner_ = nullptr;
  HWND hwnd_ = nullptr;
  HWND method_combo_ = nullptr;
  HWND type_combo_ = nullptr;
  HWND source_combo_ = nullptr;
  HWND list_view_ = nullptr;
  std::string network_json_ = "[]";
};

}  // namespace kelpie::windows
