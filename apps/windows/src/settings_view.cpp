#include "settings_view.h"

#include <commdlg.h>
#include <shlobj.h>

#include <algorithm>
#include <iterator>
#include <string>

#include "../resources/resource.h"
#include "ui_theme.h"

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
  if (length <= 0) {
    return {};
  }
  std::wstring value(static_cast<std::size_t>(length) + 1, L'\0');
  const int copied = GetWindowTextW(hwnd, value.data(), static_cast<int>(value.size()));
  value.resize(copied > 0 ? static_cast<std::size_t>(copied) : 0);
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
    case WM_ERASEBKGND: {
      RECT rect{};
      GetClientRect(hwnd, &rect);
      HBRUSH brush = CreateSolidBrush(ui::Colors().canvas);
      FillRect(reinterpret_cast<HDC>(wparam), &rect, brush);
      DeleteObject(brush);
      return TRUE;
    }
    case WM_CREATE: {
      CreateWindowExW(0, L"STATIC", L"Port (set at launch)", WS_CHILD | WS_VISIBLE,
                      16, 16, 90, 20, hwnd, nullptr, nullptr, nullptr);
      CreateWindowExW(0, L"STATIC", L"Profile (set at launch)", WS_CHILD | WS_VISIBLE,
                      16, 56, 90, 20, hwnd, nullptr, nullptr, nullptr);
      CreateWindowExW(0, L"STATIC", L"Startup URL", WS_CHILD | WS_VISIBLE,
                      16, 96, 90, 20, hwnd, nullptr, nullptr, nullptr);

      state->port_edit = CreateWindowExW(0, L"EDIT", std::to_wstring(state->values.port).c_str(),
                                         WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL | ES_READONLY, 112, 12, 240, 24,
                                         hwnd, reinterpret_cast<HMENU>(IDC_SETTINGS_PORT), nullptr, nullptr);
      state->profile_edit = CreateWindowExW(0, L"EDIT", state->values.profile_dir.c_str(),
                                            WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL | ES_READONLY, 112, 52, 240, 24,
                                            hwnd, reinterpret_cast<HMENU>(IDC_SETTINGS_PROFILE), nullptr, nullptr);
      state->url_edit = CreateWindowExW(0, L"EDIT", state->values.startup_url.c_str(),
                                        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL, 112, 92, 240, 24,
                                        hwnd, reinterpret_cast<HMENU>(IDC_SETTINGS_STARTUP_URL), nullptr, nullptr);

      HWND browse = CreateWindowExW(0, L"BUTTON", L"Browse", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
                      360, 52, 72, 24, hwnd, reinterpret_cast<HMENU>(IDC_SETTINGS_PROFILE_BROWSE),
                      nullptr, nullptr);
      EnableWindow(browse, FALSE);
      CreateWindowExW(0, L"BUTTON", L"Save", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
                      248, 136, 88, 28, hwnd, reinterpret_cast<HMENU>(IDOK), nullptr, nullptr);
      CreateWindowExW(0, L"BUTTON", L"Cancel", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
                      344, 136, 88, 28, hwnd, reinterpret_cast<HMENU>(IDCANCEL), nullptr, nullptr);
      return 0;
    }
    case WM_CTLCOLORSTATIC:
    case WM_CTLCOLOREDIT: {
      const auto colors = ui::Colors();
      SetTextColor(reinterpret_cast<HDC>(wparam), colors.text);
      SetBkColor(reinterpret_cast<HDC>(wparam), colors.canvas);
      return reinterpret_cast<LRESULT>(GetSysColorBrush(COLOR_WINDOW));
    }
    case WM_DRAWITEM: {
      const auto* item = reinterpret_cast<DRAWITEMSTRUCT*>(lparam);
      if (item == nullptr) return FALSE;
      const auto colors = ui::Colors();
      const bool pressed = (item->itemState & ODS_SELECTED) != 0;
      ui::PaintRounded(item->hDC, item->rcItem, pressed ? colors.surface_hover : colors.surface,
                       colors.border, ui::Dip(hwnd, 8));
      wchar_t label[64]{};
      GetWindowTextW(item->hwndItem, label, static_cast<int>(std::size(label)));
      SetBkMode(item->hDC, TRANSPARENT);
      SetTextColor(item->hDC, colors.text);
      DrawTextW(item->hDC, label, -1, const_cast<RECT*>(&item->rcItem),
                DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
      return TRUE;
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
          // Port and profile are launch-time capabilities. Keeping them
          // read-only avoids persisting settings the launcher cannot consume.
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
