#pragma once

#include <chrono>
#include <functional>
#include <optional>

#include <windows.h>

#include "owner_task_queue.h"

namespace kelpie::windows {

class NativeWindowControl {
 public:
  bool Create(HINSTANCE instance, HWND browser, int default_width, int default_height);
  void Shutdown();
  bool Invoke(std::function<bool()> task, std::chrono::milliseconds timeout);
  bool is_owner_thread() const { return GetCurrentThreadId() == owner_thread_id_; }

  bool SetFullscreen(bool enabled);
  bool fullscreen() const { return fullscreen_; }
  bool Resize(int width, int height);
  bool ResetViewport();
  std::optional<RECT> viewport() const;

 private:
  static LRESULT CALLBACK Proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  bool ValidBrowser() const;

  DWORD owner_thread_id_ = 0;
  HWND dispatcher_ = nullptr;
  HWND browser_ = nullptr;
  int default_width_ = 0;
  int default_height_ = 0;
  OwnerTaskQueue queue_;
  bool fullscreen_ = false;
  LONG_PTR saved_style_ = 0;
  WINDOWPLACEMENT saved_placement_{sizeof(WINDOWPLACEMENT)};
};

}  // namespace kelpie::windows
