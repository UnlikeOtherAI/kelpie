#include "win32_shell.h"

#include <commctrl.h>
#include <windowsx.h>

#include <algorithm>
#include <iterator>
#include <memory>
#include <string>

#include <nlohmann/json.hpp>

#include "../resources/resource.h"
#include "windows_utf.h"

namespace kelpie::windows {
namespace {

constexpr UINT kToastMessage = WM_APP + 1;
constexpr UINT kDpiChangedMessage = 0x02E0;
constexpr UINT_PTR kToastTimerId = 1;
constexpr int kTabHeight = 30;

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
  const bool tab_changed = RefreshTabs();
  url_bar_.SetUrl(utf::Utf8ToWide(state.url).value_or(L""), tab_changed);
  url_bar_.SetNavigationState(state.can_go_back, state.can_go_forward,
                              state.is_loading);
  if (!state.title.empty()) {
    SetWindowTextW(hwnd_,
                   (utf::Utf8ToWideDisplay(state.title) + L" - Kelpie").c_str());
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
      const ACCEL shortcuts[] = {
          {FVIRTKEY | FCONTROL, 'T', IDM_NEW_TAB},
          {FVIRTKEY | FCONTROL, 'W', IDM_CLOSE_TAB},
          {FVIRTKEY | FCONTROL, 'L', IDM_FOCUS_URL},
          {FVIRTKEY | FCONTROL, VK_TAB, IDM_NEXT_TAB},
          {FVIRTKEY | FCONTROL | FSHIFT, VK_TAB, IDM_PREVIOUS_TAB},
      };
      accelerators_ = CreateAcceleratorTableW(
          const_cast<LPACCEL>(shortcuts), static_cast<int>(std::size(shortcuts)));
      RECT rect{};
      GetClientRect(hwnd_, &rect);
      tab_strip_ = CreateWindowExW(
          0, WC_TABCONTROLW, L"", WS_CHILD | WS_VISIBLE | TCS_TABS | TCS_FOCUSNEVER,
          8, 2, 300, kTabHeight, hwnd_, reinterpret_cast<HMENU>(IDC_TAB_STRIP),
          instance_, nullptr);
      new_tab_button_ = CreateWindowExW(
          0, L"BUTTON", L"+", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 0, 0, 28,
          26, hwnd_, reinterpret_cast<HMENU>(IDC_NEW_TAB_BUTTON), instance_,
          nullptr);
      close_tab_button_ = CreateWindowExW(
          0, L"BUTTON", L"x", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 0, 0, 28,
          26, hwnd_, reinterpret_cast<HMENU>(IDC_CLOSE_TAB_BUTTON), instance_,
          nullptr);
      url_bar_.Create(hwnd_, instance_, rect, delegate_);
      browser_view_->Create(hwnd_, instance_, rect, observer_);
      toast_.Create(hwnd_, instance_);
      bookmarks_view_.SetNavigateCallback([this](const std::string& url) {
        delegate_->OnNavigateRequested(url);
      });
      history_view_.SetNavigateCallback([this](const std::string& url) {
        delegate_->OnNavigateRequested(url);
      });
      LayoutChildren(rect.right, rect.bottom);
      RefreshTabs();
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
    case WM_NOTIFY:
      if (reinterpret_cast<NMHDR*>(lparam)->idFrom == IDC_TAB_STRIP &&
          reinterpret_cast<NMHDR*>(lparam)->code == TCN_SELCHANGE) {
        ActivateSelectedTab();
        return 0;
      }
      break;
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
      if (url_bar_.HandleCommand(LOWORD(wparam), HIWORD(wparam))) return 0;
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
        case IDC_NEW_TAB_BUTTON:
        case IDM_NEW_TAB:
          delegate_->OnCreateTabRequested();
          return 0;
        case IDC_CLOSE_TAB_BUTTON:
        case IDM_CLOSE_TAB:
          CloseSelectedTab();
          return 0;
        case IDM_FOCUS_URL:
          url_bar_.Focus();
          return 0;
        case IDM_NEXT_TAB:
          ActivateAdjacentTab(1);
          return 0;
        case IDM_PREVIOUS_TAB:
          ActivateAdjacentTab(-1);
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
      if (accelerators_) {
        DestroyAcceleratorTable(accelerators_);
        accelerators_ = nullptr;
      }
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
  const int tab_top = title_bar_height + 2;
  const int tab_left = inset + 8;
  const int controls_right = std::max(tab_left + 80, width - inset - 8);
  SetWindowPos(new_tab_button_, nullptr, controls_right - 60, tab_top + 2, 28,
               26, SWP_NOZORDER);
  SetWindowPos(close_tab_button_, nullptr, controls_right - 28, tab_top + 2,
               28, 26, SWP_NOZORDER);
  SetWindowPos(tab_strip_, nullptr, tab_left, tab_top,
               std::max(40, controls_right - tab_left - 68), kTabHeight,
               SWP_NOZORDER);
  const int content_top = title_bar_height + kTabHeight;
  RECT rect{inset, content_top, width - inset, height - inset};
  url_bar_.Resize(rect);
  RECT browser_rect{inset, content_top + url_bar_.Height(), width - inset,
                    height - inset};
  browser_view_->Resize(browser_rect);
  toast_.Resize(rect);
  InvalidateRect(hwnd_, nullptr, FALSE);
}

bool Win32Shell::RefreshTabs() {
  if (tab_strip_ == nullptr || delegate_ == nullptr) return false;
  const nlohmann::json parsed =
      nlohmann::json::parse(delegate_->GetTabsJson(), nullptr, false);
  const nlohmann::json* entries =
      parsed.is_object() && parsed.contains("tabs") ? &parsed["tabs"] : &parsed;
  if (!entries->is_array()) return false;
  const int previous = TabCtrl_GetCurSel(tab_strip_);
  const std::string previous_active = active_tab_id_;
  tabs_.clear();
  TabCtrl_DeleteAllItems(tab_strip_);
  int active = -1;
  int index = 0;
  for (const auto& entry : *entries) {
    if (!entry.is_object()) continue;
    const std::string id = entry.value("id", "");
    if (id.empty()) continue;
    std::string label = entry.value("title", "");
    if (label.empty()) label = entry.value("url", "");
    if (label.empty()) label = "New tab";
    std::wstring text = utf::Utf8ToWideDisplay(label);
    TCITEMW item{};
    item.mask = TCIF_TEXT;
    item.pszText = text.data();
    TabCtrl_InsertItem(tab_strip_, index, &item);
    tabs_.push_back({id, entry.value("generation", std::uint64_t{0})});
    if (entry.value("active", false)) {
      active = index;
      active_tab_id_ = id;
    }
    ++index;
  }
  TabCtrl_SetCurSel(tab_strip_,
                    active >= 0 ? active
                                : previous >= 0 && previous < index ? previous
                                                                  : 0);
  EnableWindow(close_tab_button_, index > 0 ? TRUE : FALSE);
  if (active < 0) active_tab_id_.clear();
  return previous_active != active_tab_id_;
}

void Win32Shell::ActivateAdjacentTab(int direction) {
  if (tabs_.empty()) return;
  const int current = std::max(0, TabCtrl_GetCurSel(tab_strip_));
  const int next =
      (current + direction + static_cast<int>(tabs_.size())) %
      static_cast<int>(tabs_.size());
  TabCtrl_SetCurSel(tab_strip_, next);
  ActivateSelectedTab();
}

void Win32Shell::ActivateSelectedTab() {
  const int selected = TabCtrl_GetCurSel(tab_strip_);
  if (selected >= 0 && static_cast<std::size_t>(selected) < tabs_.size()) {
    const TabItem& tab = tabs_[static_cast<std::size_t>(selected)];
    delegate_->OnActivateTabRequested(tab.id, tab.generation);
    browser_view_->Focus();
  }
}

void Win32Shell::CloseSelectedTab() {
  const int selected = TabCtrl_GetCurSel(tab_strip_);
  if (selected >= 0 && static_cast<std::size_t>(selected) < tabs_.size()) {
    const TabItem& tab = tabs_[static_cast<std::size_t>(selected)];
    delegate_->OnCloseTabRequested(tab.id, tab.generation);
  }
}

}  // namespace kelpie::windows
