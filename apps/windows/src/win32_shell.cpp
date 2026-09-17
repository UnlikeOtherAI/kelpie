#include "win32_shell.h"

#include <windowsx.h>

#include <memory>
#include <string>

#include "../resources/resource.h"

namespace kelpie::windows {
namespace {

constexpr UINT kToastMessage = WM_APP + 1;
constexpr UINT kDpiChangedMessage = 0x02E0;
constexpr UINT_PTR kToastTimerId = 1;

}  // namespace

Win32Shell::Win32Shell(HINSTANCE instance, ShellDelegate* delegate,
                       BrowserStateObserver* observer,
                       Win32BrowserView* browser_view)
    : instance_(instance),
      delegate_(delegate),
      observer_(observer),
      browser_view_(browser_view) {}

bool Win32Shell::Create(const std::wstring& title, int width, int height) {
  WNDCLASSEXW window_class{};
  window_class.cbSize = sizeof(window_class);
  window_class.lpfnWndProc = &Win32Shell::WindowProc;
  window_class.hInstance = instance_;
  window_class.lpszClassName = L"Kelpie";
  window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  window_class.hIcon = LoadIconW(instance_, MAKEINTRESOURCEW(IDI_KELPIE));
  window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  RegisterClassExW(&window_class);

  constexpr DWORD window_style = WS_OVERLAPPED | WS_THICKFRAME |
                                 WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU |
                                 WS_CLIPCHILDREN | WS_CLIPSIBLINGS;
  hwnd_ = CreateWindowExW(0, window_class.lpszClassName, title.c_str(),
                          window_style, CW_USEDEFAULT, CW_USEDEFAULT, width,
                          height, nullptr, nullptr, instance_, this);
  if (hwnd_ != nullptr) {
    SetWindowPos(hwnd_, nullptr, 0, 0, 0, 0,
                 SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                     SWP_NOACTIVATE);
    window_chrome_.UpdateDwmFrame();
  }
  return hwnd_ != nullptr;
}

void Win32Shell::Show(int show_command) {
  if (hwnd_ == nullptr) return;
  ShowWindow(hwnd_, show_command);
  UpdateWindow(hwnd_);
}

void Win32Shell::UpdateBrowserState(const BrowserState& state) {
  if (hwnd_ == nullptr) return;
  std::wstring url(state.url.begin(), state.url.end());
  url_bar_.SetUrl(url);
  url_bar_.SetNavigationState(state.can_go_back, state.can_go_forward,
                              state.is_loading);
  if (!state.title.empty()) {
    std::wstring title(state.title.begin(), state.title.end());
    SetWindowTextW(hwnd_, (title + L" - Kelpie").c_str());
  }
}

void Win32Shell::ShowToast(const std::wstring& message) {
  if (hwnd_ == nullptr) return;
  auto* payload = new std::wstring(message);
  PostMessageW(hwnd_, kToastMessage, 0, reinterpret_cast<LPARAM>(payload));
}

void Win32Shell::Close() {
  if (hwnd_ != nullptr) DestroyWindow(hwnd_);
}

LRESULT CALLBACK Win32Shell::WindowProc(HWND hwnd, UINT message, WPARAM wparam,
                                        LPARAM lparam) {
  auto* self =
      reinterpret_cast<Win32Shell*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    self = reinterpret_cast<Win32Shell*>(create->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    self->hwnd_ = hwnd;
  }
  return self != nullptr ? self->HandleMessage(message, wparam, lparam)
                         : DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT Win32Shell::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_CREATE: {
      window_chrome_.Attach(hwnd_, instance_);
      RECT rect{};
      GetClientRect(hwnd_, &rect);
      url_bar_.Create(hwnd_, instance_, rect, delegate_);
      browser_view_->Create(hwnd_, instance_, rect, observer_);
      toast_.Create(hwnd_, instance_);
      LayoutChildren(rect.right, rect.bottom);
      return 0;
    }
    case WM_NCCALCSIZE:
      if (wparam == TRUE) {
        if (IsZoomed(hwnd_)) {
          auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
          MONITORINFO monitor_info{sizeof(monitor_info)};
          const HMONITOR monitor =
              MonitorFromWindow(hwnd_, MONITOR_DEFAULTTONEAREST);
          if (GetMonitorInfoW(monitor, &monitor_info))
            params->rgrc[0] = monitor_info.rcWork;
        }
        return 0;
      }
      break;
    case WM_NCHITTEST:
      return window_chrome_.HitTest(wparam, lparam);
    case WM_SIZE:
      if (wparam != SIZE_MINIMIZED)
        LayoutChildren(LOWORD(lparam), HIWORD(lparam));
      window_chrome_.UpdateDwmFrame();
      return 0;
    case kDpiChangedMessage: {
      const auto* suggested = reinterpret_cast<RECT*>(lparam);
      SetWindowPos(hwnd_, nullptr, suggested->left, suggested->top,
                   suggested->right - suggested->left,
                   suggested->bottom - suggested->top,
                   SWP_NOACTIVATE | SWP_NOZORDER);
      return 0;
    }
    case WM_ACTIVATE:
      window_chrome_.SetActive(LOWORD(wparam) != WA_INACTIVE);
      break;
    case WM_MOUSEMOVE: {
      POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      window_chrome_.TrackMouse(point);
      break;
    }
    case WM_MOUSELEAVE:
      window_chrome_.TrackMouseLeave();
      return 0;
    case WM_PAINT: {
      PAINTSTRUCT paint{};
      HDC device_context = BeginPaint(hwnd_, &paint);
      window_chrome_.Draw(device_context);
      EndPaint(hwnd_, &paint);
      return 0;
    }
    case WM_ERASEBKGND:
      return window_chrome_.EraseBackground(reinterpret_cast<HDC>(wparam));
    case WM_DRAWITEM: {
      const auto* item = reinterpret_cast<DRAWITEMSTRUCT*>(lparam);
      if (item != nullptr && window_chrome_.DrawControl(*item)) return TRUE;
      break;
    }
    case WM_COMMAND:
      switch (LOWORD(wparam)) {
        case IDC_WINDOW_CLOSE:
          SendMessageW(hwnd_, WM_CLOSE, 0, 0);
          return 0;
        case IDC_WINDOW_MINIMIZE:
          ShowWindow(hwnd_, SW_MINIMIZE);
          return 0;
        case IDC_WINDOW_MAXIMIZE:
          ShowWindow(hwnd_, IsZoomed(hwnd_) ? SW_RESTORE : SW_MAXIMIZE);
          return 0;
        case IDC_BACK_BUTTON:
          delegate_->OnBackRequested();
          return 0;
        case IDC_FORWARD_BUTTON:
          delegate_->OnForwardRequested();
          return 0;
        case IDC_RELOAD_BUTTON:
          delegate_->OnReloadRequested();
          return 0;
        case IDC_SETTINGS_BUTTON:
          ShowAppMenu();
          return 0;
        case IDM_SETTINGS:
          delegate_->OnOpenSettingsRequested();
          return 0;
        case IDM_VIEW_BOOKMARKS:
          bookmarks_view_.EnsureCreated(instance_, hwnd_);
          bookmarks_view_.UpdateFromJson(delegate_->GetBookmarksJson());
          bookmarks_view_.ToggleVisible();
          return 0;
        case IDM_VIEW_HISTORY:
          history_view_.EnsureCreated(instance_, hwnd_);
          history_view_.UpdateFromJson(delegate_->GetHistoryJson());
          history_view_.ToggleVisible();
          return 0;
        case IDM_VIEW_NETWORK:
          network_view_.EnsureCreated(instance_, hwnd_);
          network_view_.UpdateFromJson(delegate_->GetNetworkJson());
          network_view_.ToggleVisible();
          return 0;
        default:
          break;
      }
      break;
    case WM_SETFOCUS:
      browser_view_->Focus();
      return 0;
    case WM_TIMER:
      if (wparam == kToastTimerId) {
        KillTimer(hwnd_, kToastTimerId);
        toast_.Hide();
        return 0;
      }
      break;
    case kToastMessage: {
      std::unique_ptr<std::wstring> payload(
          reinterpret_cast<std::wstring*>(lparam));
      if (payload) {
        toast_.ShowMessage(*payload);
        KillTimer(hwnd_, kToastTimerId);
        SetTimer(hwnd_, kToastTimerId, 3000, nullptr);
      }
      return 0;
    }
    case WM_SETTEXT: {
      const LRESULT result = DefWindowProcW(hwnd_, message, wparam, lparam);
      InvalidateRect(hwnd_, nullptr, FALSE);
      return result;
    }
    case WM_CLOSE:
      delegate_->OnWindowCloseRequested();
      DestroyWindow(hwnd_);
      return 0;
    case WM_DESTROY:
      PostQuitMessage(0);
      return 0;
    default:
      break;
  }
  return DefWindowProcW(hwnd_, message, wparam, lparam);
}

void Win32Shell::ShowAppMenu() {
  HMENU menu = CreatePopupMenu();
  AppendMenuW(menu, MF_STRING, IDM_VIEW_BOOKMARKS, L"Bookmarks");
  AppendMenuW(menu, MF_STRING, IDM_VIEW_HISTORY, L"History");
  AppendMenuW(menu, MF_STRING, IDM_VIEW_NETWORK, L"Network Inspector");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, IDM_SETTINGS, L"Settings");
  RECT anchor{};
  GetWindowRect(GetDlgItem(hwnd_, IDC_SETTINGS_BUTTON), &anchor);
  const UINT command =
      TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTALIGN | TPM_TOPALIGN,
                     anchor.right, anchor.bottom, 0, hwnd_, nullptr);
  DestroyMenu(menu);
  if (command != 0) SendMessageW(hwnd_, WM_COMMAND, command, 0);
}

void Win32Shell::LayoutChildren(int width, int height) {
  window_chrome_.LayoutControls();
  const int inset = window_chrome_.Inset();
  const int title_bar_height = window_chrome_.TitleBarHeight();
  RECT rect{inset, title_bar_height, width - inset, height - inset};
  url_bar_.Resize(rect);
  RECT browser_rect{inset, title_bar_height + url_bar_.Height(), width - inset,
                    height - inset};
  browser_view_->Resize(browser_rect);
  toast_.Resize(rect);
  InvalidateRect(hwnd_, nullptr, FALSE);
}

}  // namespace kelpie::windows
