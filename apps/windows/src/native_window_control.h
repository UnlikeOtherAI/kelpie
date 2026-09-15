#pragma once
#include "owner_task_queue.h"
#include <windows.h>
namespace kelpie::windows {
class NativeWindowControl {
 public:
  bool Create(HINSTANCE, HWND browser, int default_width, int default_height);
  void Shutdown();
  bool Invoke(std::function<void()> task, std::chrono::milliseconds timeout);
  bool is_owner_thread() const { return GetCurrentThreadId() == owner_thread_id_; }
  void SetFullscreen(bool enabled); bool fullscreen() const { return fullscreen_; }
  void Resize(int width, int height);
  void ResetViewport();
  RECT viewport() const;
 private:
  static LRESULT CALLBACK Proc(HWND, UINT, WPARAM, LPARAM);
  DWORD owner_thread_id_=0;
  HWND dispatcher_=nullptr; HWND browser_=nullptr; int default_width_=0, default_height_=0;
  OwnerTaskQueue queue_; bool fullscreen_=false; LONG_PTR saved_style_=0; WINDOWPLACEMENT saved_placement_{sizeof(WINDOWPLACEMENT)};
};
}
