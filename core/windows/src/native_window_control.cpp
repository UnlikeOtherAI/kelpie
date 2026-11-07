#include "native_window_control.h"

namespace kelpie::windows {
namespace {
constexpr UINT kRunOwnerTask = WM_APP + 0x531;
constexpr wchar_t kDispatcherClass[] = L"KelpieNativeControl";
}

bool NativeWindowControl::Create(HINSTANCE instance, HWND browser, int, int) {
  if (!browser || !IsWindow(browser)) return false;
  owner_thread_id_ = GetCurrentThreadId();
  browser_ = browser;
  RECT measured{};
  if (!GetClientRect(browser_, &measured) || measured.right <= measured.left || measured.bottom <= measured.top) return false;
  default_width_ = measured.right - measured.left;
  default_height_ = measured.bottom - measured.top;
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = Proc;
  window_class.hInstance = instance;
  window_class.lpszClassName = kDispatcherClass;
  if (!RegisterClassW(&window_class) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return false;
  dispatcher_ = CreateWindowExW(0, kDispatcherClass, L"", 0, 0, 0, 0, 0,
                                HWND_MESSAGE, nullptr, instance, this);
  return dispatcher_ != nullptr;
}

void NativeWindowControl::Shutdown() {
  queue_.Cancel();
  if (dispatcher_ && IsWindow(dispatcher_)) DestroyWindow(dispatcher_);
  dispatcher_ = nullptr;
}

bool NativeWindowControl::Invoke(std::function<bool()> task, std::chrono::milliseconds timeout) {
  if (!dispatcher_ || !task) return false;
  if (is_owner_thread()) {
    try { return task(); } catch (...) { return false; }
  }
  const auto pending = queue_.Enqueue(std::move(task));
  if (!PostMessageW(dispatcher_, kRunOwnerTask, 0, 0)) {
    queue_.Abandon(pending);
    return false;
  }
  return queue_.Wait(pending, timeout);
}

bool NativeWindowControl::SetFullscreen(bool enabled) {
  if (!ValidBrowser() || enabled == fullscreen_) return ValidBrowser();
  HWND top = GetAncestor(browser_, GA_ROOT);
  if (!top) return false;
  if (enabled) {
    SetLastError(ERROR_SUCCESS);
    const LONG_PTR style = GetWindowLongPtrW(top, GWL_STYLE);
    if (style == 0 && GetLastError() != ERROR_SUCCESS) return false;
    WINDOWPLACEMENT placement{sizeof(WINDOWPLACEMENT)};
    if (!GetWindowPlacement(top, &placement)) return false;
    MONITORINFO monitor{sizeof(MONITORINFO)};
    if (!GetMonitorInfoW(MonitorFromWindow(top, MONITOR_DEFAULTTONEAREST), &monitor)) return false;
    SetLastError(ERROR_SUCCESS);
    SetWindowLongPtrW(top, GWL_STYLE, style & ~WS_OVERLAPPEDWINDOW);
    if (GetLastError() != ERROR_SUCCESS) return false;
    if (!SetWindowPos(top, HWND_TOP, monitor.rcMonitor.left, monitor.rcMonitor.top,
                      monitor.rcMonitor.right - monitor.rcMonitor.left, monitor.rcMonitor.bottom - monitor.rcMonitor.top,
                      SWP_FRAMECHANGED | SWP_SHOWWINDOW)) return false;
    saved_style_ = style;
    saved_placement_ = placement;
    fullscreen_ = true;
    return true;
  }
  SetLastError(ERROR_SUCCESS);
  SetWindowLongPtrW(top, GWL_STYLE, saved_style_);
  if (GetLastError() != ERROR_SUCCESS || !SetWindowPlacement(top, &saved_placement_) ||
      !SetWindowPos(top, nullptr, 0, 0, 0, 0, SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER)) return false;
  fullscreen_ = false;
  return true;
}

bool NativeWindowControl::Resize(int width, int height) {
  if (!ValidBrowser() || width < 1 || height < 1) return false;
  HWND top = GetAncestor(browser_, GA_ROOT);
  RECT current{};
  RECT outer{};
  if (!top || !GetClientRect(browser_, &current) || !GetWindowRect(top, &outer)) return false;
  const int current_width = current.right - current.left;
  const int current_height = current.bottom - current.top;
  if (!SetWindowPos(top, nullptr, outer.left, outer.top,
                    (outer.right - outer.left) + width - current_width,
                    (outer.bottom - outer.top) + height - current_height, SWP_NOZORDER)) return false;
  const auto actual = viewport();
  return actual && actual->right - actual->left == width && actual->bottom - actual->top == height;
}

bool NativeWindowControl::ResetViewport() { return Resize(default_width_, default_height_); }

std::optional<RECT> NativeWindowControl::viewport() const {
  RECT rect{};
  return ValidBrowser() && GetClientRect(browser_, &rect) ? std::optional<RECT>(rect) : std::nullopt;
}

LRESULT CALLBACK NativeWindowControl::Proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<NativeWindowControl*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    self = static_cast<NativeWindowControl*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  }
  if (message == kRunOwnerTask && self) { self->queue_.RunOne(); return 0; }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

bool NativeWindowControl::ValidBrowser() const { return browser_ && IsWindow(browser_); }

}  // namespace kelpie::windows
