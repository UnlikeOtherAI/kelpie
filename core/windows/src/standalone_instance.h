#pragma once

#include <windows.h>

namespace kelpie::windows {

// A fixed kernel object fences all standalone copies, profiles and ports. CEF
// children and containing apps never acquire it. Windows releases the handle
// even when the browser crashes; there is no stale PID or lock file to repair.
class StandaloneInstance {
 public:
  explicit StandaloneInstance(const wchar_t* name = L"Global\\UnlikeOtherAI.Kelpie.Standalone") {
    handle_ = CreateMutexW(nullptr, FALSE, name);
    error_ = handle_ ? (GetLastError() == ERROR_ALREADY_EXISTS ? ERROR_ALREADY_EXISTS : ERROR_SUCCESS)
                     : GetLastError();
  }
  ~StandaloneInstance() { if (handle_) CloseHandle(handle_); }
  StandaloneInstance(const StandaloneInstance&) = delete;
  StandaloneInstance& operator=(const StandaloneInstance&) = delete;
  DWORD error() const { return error_; }

  static void ActivateExisting() {
    EnumWindows([](HWND window, LPARAM) -> BOOL {
      if (!GetPropW(window, L"UnlikeOtherAI.Kelpie.Standalone")) return TRUE;
      if (IsIconic(window)) ShowWindowAsync(window, SW_RESTORE);
      SetForegroundWindow(window);
      return FALSE;
    }, 0);
  }

 private:
  HANDLE handle_ = nullptr;
  DWORD error_ = ERROR_SUCCESS;
};

}  // namespace kelpie::windows
