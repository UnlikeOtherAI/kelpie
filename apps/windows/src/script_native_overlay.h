#pragma once
#include <windows.h>
#include <functional>
#include <nlohmann/json.hpp>
namespace kelpie::windows {
// Native layered presentation is scoped to renderer bounds and never sends page hover events.
class ScriptNativeOverlay {
 public:
  ScriptNativeOverlay(HWND viewport, HWND owner);
  ~ScriptNativeOverlay();
  void Show(const nlohmann::json& presentation, std::function<void()> stop);
 private:
  static LRESULT CALLBACK StopProc(HWND,UINT,WPARAM,LPARAM);
  HWND viewport_, owner_, canvas_ = nullptr, stop_window_ = nullptr, button_ = nullptr;
  std::function<void()> stop_;
  nlohmann::json shown_;
  ULONGLONG shown_at_=0;
};
}
