#include "settings_view.h"

#include <commdlg.h>
#include <shlobj.h>

#include <algorithm>
#include <string>

#include "../resources/resource.h"

namespace kelpie::windows {
namespace {

class SettingsDialogState {
 public:
  SettingsDialogState(const SettingsValues& initial, SettingsValues& output)
      : values(initial), output_ref(output) {}

  SettingsValues values;
  SettingsValues& output_ref;
  bool accepted = false;
  bool done = false;
  HWND port_edit = nullptr;
  HWND profile_edit = nullptr;
  HWND url_edit = nullptr;
};

std::wstring WindowText(HWND hwnd) {
  const int length = GetWindowTextLengthW(hwnd);
  std::wstring value(static_cast<std::size_t>(length), L'\0');
  GetWindowTextW(hwnd, value.data(), length + 1);
  return value;
}

LRESULT CALLBACK SettingsProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* state = reinterpret_cast<SettingsDialogState*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    state = reinterpret_cast<SettingsDialogState*>(create->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
  }

  switch (message) {
    case WM_CREATE: {
      CreateWindowExW(0, L"STATIC", L"Port", WS_CHILD | WS_VISIBLE,
                      16, 16, 90, 20, hwnd, nullptr, nullptr, nullptr);
      CreateWindowExW(0, L"STATIC", L"Profile Dir", WS_CHILD | WS_VISIBLE,
                      16, 56, 90, 20, hwnd, nullptr, nullptr, nullptr);
      CreateWindowExW(0, L"STATIC", L"Startup URL", WS_CHILD | WS_VISIBLE,
                      16, 96, 90, 20, hwnd, nullptr, nullptr, nullptr);

      state->port_edit = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", std::to_wstring(state->values.port).c_str(),
                                         WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL, 112, 12, 240, 24,
                                         hwnd, reinterpret_cast<HMENU>(IDC_SETTINGS_PORT), nullptr, nullptr);
      state->profile_edit = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", state->values.profile_dir.c_str(),
                                            WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL, 112, 52, 240, 24,
                                            hwnd, reinterpret_cast<HMENU>(IDC_SETTINGS_PROFILE), nullptr, nullptr);
      state->url_edit = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", state->values.startup_url.c_str(),
                                        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL, 112, 92, 240, 24,
                                        hwnd, reinterpret_cast<HMENU>(IDC_SETTINGS_STARTUP_URL), nullptr, nullptr);

      CreateWindowExW(0, L"BUTTON", L"Browse", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                      360, 52, 72, 24, hwnd, reinterpret_cast<HMENU>(IDC_SETTINGS_PROFILE_BROWSE),
                      nullptr, nullptr);
      CreateWindowExW(0, L"BUTTON", L"OK", WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON,
                      248, 136, 88, 28, hwnd, reinterpret_cast<HMENU>(IDOK), nullptr, nullptr);
      CreateWindowExW(0, L"BUTTON", L"Cancel", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                      344, 136, 88, 28, hwnd, reinterpret_cast<HMENU>(IDCANCEL), nullptr, nullptr);
      return 0;
    }
    case WM_COMMAND:
      switch (LOWORD(wparam)) {
        case IDC_SETTINGS_PROFILE_BROWSE: {
          BROWSEINFOW browse{};
          browse.hwndOwner = hwnd;
          browse.lpszTitle = L"Choose profile directory";
          PIDLIST_ABSOLUTE result = SHBrowseForFolderW(&browse);
          if (result != nullptr) {
            wchar_t path[MAX_PATH]{};
            if (SHGetPathFromIDListW(result, path)) {
              SetWindowTextW(state->profile_edit, path);
            }
            CoTaskMemFree(result);
          }
          return 0;
        }
        case IDOK:
          state->values.port = std::max(1, _wtoi(WindowText(state->port_edit).c_str()));
          state->values.profile_dir = WindowText(state->profile_edit);
          state->values.startup_url = WindowText(state->url_edit);
          state->output_ref = state->values;
          state->accepted = true;
          state->done = true;
          DestroyWindow(hwnd);
          return 0;
        case IDCANCEL:
          state->done = true;
          DestroyWindow(hwnd);
          return 0;
        default:
          break;
      }
      break;
    case WM_CLOSE:
      state->done = true;
      DestroyWindow(hwnd);
      return 0;
    default:
      break;
  }
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

}  // namespace

bool SettingsView::ShowModal(HINSTANCE instance,
                             HWND owner,
                             const SettingsValues& initial_values,
                             SettingsValues& updated_values) {
  const wchar_t kClassName[] = L"KelpieSettingsDialog";
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = &SettingsProc;
  window_class.hInstance = instance;
  window_class.lpszClassName = kClassName;
  window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  RegisterClassW(&window_class);

  SettingsDialogState state(initial_values, updated_values);
  HWND dialog = CreateWindowExW(WS_EX_DLGMODALFRAME, kClassName, L"Settings",
                                WS_POPUP | WS_CAPTION | WS_SYSMENU, CW_USEDEFAULT, CW_USEDEFAULT,
                                456, 210, owner, nullptr, instance, &state);
  if (dialog == nullptr) {
    return false;
  }

  EnableWindow(owner, FALSE);
  ShowWindow(dialog, SW_SHOW);
  SetForegroundWindow(dialog);

  MSG message{};
  while (!state.done && GetMessageW(&message, nullptr, 0, 0) > 0) {
    if (!IsDialogMessageW(dialog, &message)) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
  }

  EnableWindow(owner, TRUE);
  SetForegroundWindow(owner);
  return state.accepted;
}

}  // namespace kelpie::windows
