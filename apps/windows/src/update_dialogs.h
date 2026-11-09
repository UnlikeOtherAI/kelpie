#pragma once
#include <windows.h>
#include <commctrl.h>
#include <string>

namespace kelpie::windows::updates_ui {
inline HRESULT Prompt(HWND owner, const std::wstring& version, int& choice,
    const wchar_t* title = L"Kelpie update") {
  const std::wstring text = L"Kelpie " + version + L" is available. Update now?\n\nUpdate downloads, verifies and installs the new version, then restarts Kelpie. Not now asks again next time you start the app.";
  const TASKDIALOG_BUTTON buttons[] = {{100, L"Update"}, {101, L"Skip version"}, {102, L"Not now"}};
  TASKDIALOGCONFIG dialog{}; dialog.cbSize = sizeof(dialog); dialog.hwndParent = owner;
  dialog.dwFlags = TDF_ALLOW_DIALOG_CANCELLATION | TDF_SIZE_TO_CONTENT;
  dialog.pszWindowTitle = title; dialog.pszMainInstruction = L"A new Kelpie version is available";
  dialog.pszContent = text.c_str(); dialog.cButtons = 3; dialog.pButtons = buttons; dialog.nDefaultButton = 102;
  choice = 102;
  return TaskDialogIndirect(&dialog, &choice, nullptr, nullptr);
}

inline HWND Progress(HWND owner) {
  RECT bounds{100, 100, 600, 300}; if (owner) GetWindowRect(owner, &bounds);
  const auto window = CreateWindowExW(WS_EX_DLGMODALFRAME, L"#32770", L"Updating Kelpie",
      WS_POPUP | WS_CAPTION | WS_VISIBLE, bounds.left + 80, bounds.top + 100, 500, 110,
      owner, nullptr, GetModuleHandleW(nullptr), nullptr);
  if (window) CreateWindowExW(0, L"STATIC",
      L"Downloading and verifying update\u2026\nKelpie will restart when ready.",
      WS_CHILD | WS_VISIBLE, 20, 15, 460, 60, window, nullptr, GetModuleHandleW(nullptr), nullptr);
  return window;
}
}
