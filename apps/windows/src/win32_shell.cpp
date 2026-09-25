#include "win32_shell.h"

#include <commctrl.h>
#include <windowsx.h>

#include <algorithm>
#include <array>
#include <memory>
#include <string>

#include <nlohmann/json.hpp>

#include "../resources/resource.h"
#include "theme/theme.h"
#include "windows_utf.h"

namespace kelpie::windows {
namespace {
constexpr UINT kToastMessage = WM_APP + 1;
constexpr UINT_PTR kToastTimerId = 1;
constexpr int kTabCloseFirst = 2000;

bool IsTabClose(UINT id) { return id >= kTabCloseFirst && id < kTabCloseFirst + 256; }
}  // namespace

Win32Shell::Win32Shell(HINSTANCE instance, ShellDelegate* delegate, BrowserStateObserver* observer,
                       Win32BrowserView* browser_view)
    : instance_(instance), delegate_(delegate), observer_(observer), browser_view_(browser_view) {}

bool Win32Shell::Create(const std::wstring& title, int width, int height, std::optional<POINT> origin) {
  WNDCLASSEXW window_class{};
  window_class.cbSize = sizeof(window_class);
  window_class.lpfnWndProc = &Win32Shell::WindowProc;
  window_class.hInstance = instance_;
  window_class.lpszClassName = L"Kelpie";
  window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  window_class.hIcon = LoadIconW(instance_, MAKEINTRESOURCEW(IDI_KELPIE));
  window_class.hbrBackground = nullptr;
  RegisterClassExW(&window_class);
  constexpr DWORD style = WS_OVERLAPPED | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX |
                          WS_SYSMENU | WS_CLIPCHILDREN | WS_CLIPSIBLINGS;
  hwnd_ = CreateWindowExW(0, window_class.lpszClassName, title.c_str(), style,
                          origin ? origin->x : CW_USEDEFAULT, origin ? origin->y : CW_USEDEFAULT, width, height, nullptr, nullptr, instance_, this);
  if (hwnd_ != nullptr) {
    SetWindowPos(hwnd_, nullptr, 0, 0, 0, 0, SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
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
  const bool favorites_changed = favorites_bar_.Update(delegate_->GetBookmarksJson());
  if (favorites_changed) { RECT r{}; GetClientRect(hwnd_, &r); LayoutChildren(r.right, r.bottom); }
  const bool tab_changed = RefreshTabs();
  const bool state_changed = !has_browser_state_ || state.url != browser_state_.url ||
      state.title != browser_state_.title || state.is_loading != browser_state_.is_loading ||
      state.can_go_back != browser_state_.can_go_back || state.can_go_forward != browser_state_.can_go_forward;
  if (!state_changed && !tab_changed) return;
  if (state_changed || tab_changed) {
    url_bar_.SetUrl(utf::Utf8ToWide(state.url).value_or(L""), tab_changed);
  }
  if (state_changed) {
    url_bar_.SetNavigationState(state.can_go_back, state.can_go_forward, state.is_loading);
    if (!state.title.empty()) SetWindowTextW(hwnd_, (utf::Utf8ToWideDisplay(state.title) + L" - Kelpie").c_str());
  }
  browser_state_ = state;
  has_browser_state_ = true;
}

void Win32Shell::ShowToast(const std::wstring& message) {
  if (hwnd_ != nullptr) PostMessageW(hwnd_, kToastMessage, 0, reinterpret_cast<LPARAM>(new std::wstring(message)));
}

void Win32Shell::Close() { if (hwnd_ != nullptr) DestroyWindow(hwnd_); }

bool Win32Shell::HandleKeyboardNavigation(const MSG& message) {
  if (message.message != WM_KEYDOWN || message.wParam != VK_TAB || hwnd_ == nullptr) return false;
  const std::vector<HWND> controls = FocusOrder();
  if (controls.empty()) return false;
  const HWND focused = GetFocus();
  const auto found = std::find(controls.begin(), controls.end(), focused);
  // A renderer child owns ordinary page Tab traversal. The shell only cycles
  // controls after native chrome already owns keyboard focus.
  if (focused == nullptr || focused == browser_view_->hwnd() ||
      IsChild(browser_view_->hwnd(), focused) || found == controls.end()) {
    return false;
  }
  const bool reverse = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
  std::size_t next = 0;
  if (reverse) {
    next = found == controls.begin() ? controls.size() - 1 : static_cast<std::size_t>(found - controls.begin() - 1);
  } else {
    next = static_cast<std::size_t>((found - controls.begin() + 1) % controls.size());
  }
  SetFocus(controls[next]);
  return true;
}

LRESULT CALLBACK Win32Shell::WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<Win32Shell*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    self = static_cast<Win32Shell*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    self->hwnd_ = hwnd;
  }
  return self != nullptr ? self->HandleMessage(message, wparam, lparam) : DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT CALLBACK Win32Shell::TabStripProc(HWND hwnd, UINT message, WPARAM wparam,
                                          LPARAM lparam, UINT_PTR subclass_id,
                                          DWORD_PTR reference_data) {
  auto* self = reinterpret_cast<Win32Shell*>(reference_data);
  if (self && message == WM_NCHITTEST) {
    const auto hit = self->window_chrome_.HitTest(wparam, lparam);
    if (hit >= HTLEFT && hit <= HTBOTTOMRIGHT) return HTTRANSPARENT;
    TCHITTESTINFO info{};
    info.pt = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
    ScreenToClient(hwnd, &info.pt);
    if (TabCtrl_HitTest(hwnd, &info) < 0) return HTTRANSPARENT;
  }
  if (self && (message == WM_PAINT || message == WM_PRINTCLIENT)) {
    PAINTSTRUCT ps{};
    HDC dc = message == WM_PAINT ? BeginPaint(hwnd, &ps) : reinterpret_cast<HDC>(wparam);
    self->PaintTabStrip(dc);
    if (message == WM_PAINT) EndPaint(hwnd, &ps);
    return 0;
  }
  if (message == WM_ERASEBKGND) return TRUE;
  const bool relayout = message == WM_HSCROLL || message == WM_MOUSEWHEEL ||
                        message == WM_KEYDOWN || message == WM_LBUTTONUP ||
                        message == TCM_SETCURFOCUS;
  const LRESULT result = DefSubclassProc(hwnd, message, wparam, lparam);
  if (message == WM_NCDESTROY) {
    RemoveWindowSubclass(hwnd, &Win32Shell::TabStripProc, subclass_id);
  } else if (relayout && self != nullptr) {
    self->LayoutTabCloseButtons();
  }
  return result;
}

LRESULT Win32Shell::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_CREATE: {
      window_chrome_.Attach(hwnd_, instance_);
      const ACCEL shortcuts[] = {{FVIRTKEY | FCONTROL, 'T', IDM_NEW_TAB}, {FVIRTKEY | FCONTROL, 'W', IDM_CLOSE_TAB},
                                 {FVIRTKEY | FCONTROL, 'L', IDM_FOCUS_URL}, {FVIRTKEY | FCONTROL, VK_TAB, IDM_NEXT_TAB},
                                 {FVIRTKEY | FCONTROL | FSHIFT, VK_TAB, IDM_PREVIOUS_TAB},
                                 {FVIRTKEY | FCONTROL | FSHIFT, 'N', IDM_NEW_ISOLATED_TAB}};
      accelerators_ = CreateAcceleratorTableW(const_cast<LPACCEL>(shortcuts), static_cast<int>(std::size(shortcuts)));
      RECT rect{};
      GetClientRect(hwnd_, &rect);
      // TCS_FIXEDWIDTH is what makes TabCtrl_SetItemSize mean anything: without
      // it the control sizes each tab to its own label, so pills come out
      // ragged and the shared-width rule never applies.
      tab_strip_ = CreateWindowExW(0, WC_TABCONTROLW, L"", WS_CHILD | WS_VISIBLE | WS_TABSTOP |
                                   WS_CLIPSIBLINGS | WS_CLIPCHILDREN | TCS_BUTTONS | TCS_FLATBUTTONS | TCS_OWNERDRAWFIXED |
                                   TCS_FIXEDWIDTH,
                                   0, 0, 0, 0, hwnd_, reinterpret_cast<HMENU>(IDC_TAB_STRIP), instance_, nullptr);
      SetWindowSubclass(tab_strip_, &Win32Shell::TabStripProc, 1,
                        reinterpret_cast<DWORD_PTR>(this));
      new_tab_button_ = CreateWindowExW(0, L"BUTTON", L"New tab", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
                                        0, 0, 0, 0, hwnd_, reinterpret_cast<HMENU>(IDC_NEW_TAB_BUTTON), instance_, nullptr);
      SetWindowSubclass(new_tab_button_, &Win32Shell::NewTabProc, 1, reinterpret_cast<DWORD_PTR>(this));
      favorites_bar_.Attach(hwnd_, instance_, [this](const std::string& url) { delegate_->OnNavigateRequested(url); });
      url_bar_.Create(hwnd_, instance_, rect, delegate_);
      UpdateChromePalette();
      browser_view_->Create(hwnd_, instance_, rect, observer_);
      toast_.Create(hwnd_, instance_);
      bookmarks_view_.SetNavigateCallback([this](const std::string& url) { delegate_->OnNavigateRequested(url); });
      history_view_.SetNavigateCallback([this](const std::string& url) { delegate_->OnNavigateRequested(url); });
      LayoutChildren(rect.right, rect.bottom);
      RefreshTabs();
      return 0;
    }
    case WM_NCCALCSIZE:
      if (wparam == TRUE) return window_chrome_.CalcClientArea(reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam));
      break;
    case WM_NCHITTEST: return window_chrome_.HitTest(wparam, lparam);
    case WM_GETMINMAXINFO: {
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      info->ptMinTrackSize.x = ui::Dip(hwnd_, 720);
      info->ptMinTrackSize.y = ui::Dip(hwnd_, 480);
      return 0;
    }
    case WM_SIZE:
      if (wparam != SIZE_MINIMIZED) LayoutChildren(LOWORD(lparam), HIWORD(lparam));
      window_chrome_.UpdateDwmFrame();
      return 0;
    case ui::kDpiChangedMessage: {
      const auto* suggested = reinterpret_cast<RECT*>(lparam);
      SetWindowPos(hwnd_, nullptr, suggested->left, suggested->top, suggested->right - suggested->left,
                   suggested->bottom - suggested->top, SWP_NOACTIVATE | SWP_NOZORDER);
      // Metrics and owned fonts are per-monitor, so a move between differently
      // scaled displays has to rebuild them rather than rescale stale pixels.
      ApplyAppearance();
      return 0;
    }
    case WM_SETTINGCHANGE:
    case WM_THEMECHANGED:
    case WM_SYSCOLORCHANGE:
      if (ui::IsAppearanceChange(message, lparam)) {
        ui::InvalidateAppearanceCache();
        ApplyAppearance();
      }
      break;
    case WM_ACTIVATE: window_chrome_.SetActive(LOWORD(wparam) != WA_INACTIVE); break;
    case WM_MOUSEMOVE: {
      window_chrome_.TrackMouse({GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)});
      break;
    }
    case WM_MOUSELEAVE: window_chrome_.TrackMouseLeave(); return 0;
    case WM_PAINT: {
      PAINTSTRUCT paint{};
      HDC dc = BeginPaint(hwnd_, &paint);
      PaintClient(dc);
      EndPaint(hwnd_, &paint);
      return 0;
    }
    case WM_PRINTCLIENT:
      PaintClient(reinterpret_cast<HDC>(wparam));
      return 0;
    case WM_PRINT: return DefWindowProcW(hwnd_, message, wparam, lparam);
    case WM_ERASEBKGND: return window_chrome_.EraseBackground(reinterpret_cast<HDC>(wparam));
    case WM_CTLCOLORSTATIC:
    case WM_CTLCOLOREDIT: {
      HBRUSH brush = nullptr;
      if (url_bar_.ControlColor(reinterpret_cast<HDC>(wparam), reinterpret_cast<HWND>(lparam), &brush)) return reinterpret_cast<LRESULT>(brush);
      break;
    }
    case WM_DRAWITEM: {
      const auto* item = reinterpret_cast<DRAWITEMSTRUCT*>(lparam);
      if (item != nullptr && DrawControl(*item)) return TRUE;
      break;
    }
    case WM_NOTIFY: {
      const auto* notice = reinterpret_cast<NMHDR*>(lparam);
      if (notice != nullptr && notice->idFrom == IDC_TAB_STRIP && notice->code == TCN_SELCHANGE) {
        LayoutTabCloseButtons();
        ActivateSelectedTab();
        return 0;
      }
      break;
    }
    case WM_COMMAND: {
      const UINT id = LOWORD(wparam);
      if (favorites_bar_.HandleCommand(id)) return 0;
      if (url_bar_.HandleCommand(id, HIWORD(wparam))) return 0;
      if (IsTabClose(id)) {
        const std::size_t index = id - kTabCloseFirst;
        if (index < tab_close_buttons_.size()) delegate_->OnCloseTabRequested(tab_close_buttons_[index].id, tab_close_buttons_[index].generation);
        return 0;
      }
      switch (id) {
        case IDC_WINDOW_CLOSE: SendMessageW(hwnd_, WM_CLOSE, 0, 0); return 0;
        case IDC_WINDOW_MINIMIZE: ShowWindow(hwnd_, SW_MINIMIZE); return 0;
        case IDC_WINDOW_MAXIMIZE: ShowWindow(hwnd_, IsZoomed(hwnd_) ? SW_RESTORE : SW_MAXIMIZE); return 0;
        case IDC_ACCOUNT_BUTTON: delegate_->OnAccountRequested(); return 0;
        case IDC_HOME_BUTTON: delegate_->OnHomeRequested(); return 0;
        case IDC_ADD_FAVORITE_BUTTON: delegate_->OnAddFavoriteRequested(); return 0;
        case IDC_BACK_BUTTON: delegate_->OnBackRequested(); return 0;
        case IDC_FORWARD_BUTTON: delegate_->OnForwardRequested(); return 0;
        case IDC_RELOAD_BUTTON: delegate_->OnReloadRequested(); return 0;
        case IDC_BOOKMARKS_BUTTON: ShowPanel(IDM_VIEW_BOOKMARKS); return 0;
        case IDC_HISTORY_BUTTON: ShowPanel(IDM_VIEW_HISTORY); return 0;
        case IDC_NETWORK_BUTTON: ShowPanel(IDM_VIEW_NETWORK); return 0;
        case IDC_SETTINGS_BUTTON:
        case IDM_SETTINGS: delegate_->OnOpenSettingsRequested(); return 0;
        case IDC_NEW_TAB_BUTTON:
          delegate_->OnCreateTabRequested();
          return 0;
        case IDM_NEW_TAB: delegate_->OnCreateTabRequested(); return 0;
        case IDM_NEW_ISOLATED_TAB: delegate_->OnCreateIsolatedTabRequested(); return 0;
        case IDM_CLOSE_TAB: { const int selected = TabCtrl_GetCurSel(tab_strip_); if (selected >= 0) CloseTabAt(static_cast<std::size_t>(selected)); return 0; }
        case IDM_FOCUS_URL: url_bar_.Focus(); return 0;
        case IDM_NEXT_TAB: ActivateAdjacentTab(1); return 0;
        case IDM_PREVIOUS_TAB: ActivateAdjacentTab(-1); return 0;
        default: break;
      }
      break;
    }
    case WM_SETFOCUS:
      if (GetFocus() == hwnd_) browser_view_->Focus();
      return 0;
    case WM_TIMER:
      if (wparam == 2) { UpdateChromePalette(); if (!chrome_transition_.Active(GetTickCount64())) KillTimer(hwnd_, 2); return 0; }
      if (wparam == kToastTimerId) { KillTimer(hwnd_, kToastTimerId); toast_.Hide(); return 0; }
      break;
    case kToastMessage: {
      std::unique_ptr<std::wstring> payload(reinterpret_cast<std::wstring*>(lparam));
      if (payload) { toast_.ShowMessage(*payload); KillTimer(hwnd_, kToastTimerId); SetTimer(hwnd_, kToastTimerId, 3000, nullptr); }
      return 0;
    }
    case WM_SETTEXT: {
      const LRESULT result = DefWindowProcW(hwnd_, message, wparam, lparam);
      InvalidateRect(hwnd_, nullptr, FALSE);
      return result;
    }
    case WM_CLOSE: delegate_->OnWindowCloseRequested(); return 0;
    case WM_DESTROY:
      url_bar_.Destroy();
      tab_tooltips_.Destroy();
      if (accelerators_ != nullptr) DestroyAcceleratorTable(accelerators_);
      PostQuitMessage(0);
      return 0;
    default: break;
  }
  return DefWindowProcW(hwnd_, message, wparam, lparam);
}

void Win32Shell::ShowPanel(UINT command) {
  if (command == IDM_VIEW_BOOKMARKS) { bookmarks_view_.EnsureCreated(instance_, hwnd_); bookmarks_view_.UpdateFromJson(delegate_->GetBookmarksJson()); bookmarks_view_.ToggleVisible(); }
  if (command == IDM_VIEW_HISTORY) { history_view_.EnsureCreated(instance_, hwnd_); history_view_.UpdateFromJson(delegate_->GetHistoryJson()); history_view_.ToggleVisible(); }
  if (command == IDM_VIEW_NETWORK) { network_view_.EnsureCreated(instance_, hwnd_); network_view_.UpdateFromJson(delegate_->GetNetworkJson()); network_view_.ToggleVisible(); }
}

void Win32Shell::ApplyAppearance() {
  if (hwnd_ == nullptr) return;
  window_chrome_.UpdateDwmFrame();
  UpdateChromePalette();
  url_bar_.RefreshTheme();
  RECT rect{};
  GetClientRect(hwnd_, &rect);
  LayoutChildren(rect.right, rect.bottom);
  // Owner-drawn children cache nothing, but the native EDIT and ListView
  // controls keep their own themed brushes and must be told to redraw.
  RedrawWindow(hwnd_, nullptr, nullptr,
               RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN | RDW_UPDATENOW);
}

void Win32Shell::ApplyTabMetrics() {
  if (tab_strip_ == nullptr || hwnd_ == nullptr) return;
  RECT strip{};
  GetWindowRect(tab_strip_, &strip);
  const int strip_width = strip.right - strip.left;
  if (strip_width <= 0) return;
  TabCtrl_SetItemSize(tab_strip_, TabWidthFor(strip_width),
                      ui::Dip(hwnd_, 44));
  LayoutTabCloseButtons();
}

int Win32Shell::TabWidthFor(int strip_width) const {
  // Mirrors TabBarCoordinator.relayout in the macOS app: pills share the
  // available width, clamped so a lone tab does not stretch across the window
  // and a crowded strip stays readable and scrolls instead of shrinking away.
  const int minimum = ui::Dip(hwnd_, kTabMinWidthDip);
  const int maximum = ui::Dip(hwnd_, kTabMaxWidthDip);
  const int count = static_cast<int>(tabs_.size());
  if (count <= 0 || strip_width <= 0) return maximum;
  return std::clamp(strip_width / count, minimum, maximum);
}

void Win32Shell::LayoutChildren(int width, int height) {
  window_chrome_.LayoutControls();
  const int inset = window_chrome_.Inset();
  const int title = window_chrome_.TitleBarHeight();
  RECT toolbar{inset, title, width - inset, height - inset};
  url_bar_.Resize(toolbar);
  const int leading = ui::Dip(hwnd_, 56);
  const int tab_top = ui::Dip(hwnd_, 8);
  const int strip_width = std::max(1, width - leading - window_chrome_.ControlsWidth() - ui::Dip(hwnd_, 40));
  SetWindowPos(tab_strip_, nullptr, leading, tab_top, strip_width, title - tab_top, SWP_NOZORDER);
  SetWindowPos(new_tab_button_, nullptr, inset + ui::Dip(hwnd_, 6), tab_top,
               ui::Dip(hwnd_, 42), ui::Dip(hwnd_, 38), SWP_NOZORDER);
  ApplyTabMetrics();
  LayoutTabCloseButtons();
  const int favorite_top = title + url_bar_.Height();
  favorites_bar_.Layout(RECT{inset, favorite_top, width-inset, favorite_top+favorites_bar_.Height()});
  RECT browser{inset, favorite_top + favorites_bar_.Height() + 1, width - inset, height - inset};
  browser_view_->Resize(browser);
  toast_.Resize(browser);
  InvalidateRect(hwnd_, nullptr, FALSE);
}

void Win32Shell::PaintClient(HDC device_context) const {
  RECT rect{};
  GetClientRect(hwnd_, &rect);
  RECT chrome{rect.left, rect.top, rect.right, window_chrome_.TitleBarHeight()+url_bar_.Height()+favorites_bar_.Height()+1};
  ui::FillSolid(device_context, chrome, chrome_palette_.bar);
  window_chrome_.Draw(device_context);
  const RECT line{1, chrome.bottom-1, rect.right-1, chrome.bottom};
  ui::FillSolid(device_context, line, chrome_palette_.line);
  url_bar_.Paint(device_context);
}

}  // namespace kelpie::windows
