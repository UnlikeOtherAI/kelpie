#include "win32_shell.h"

#include <commctrl.h>
#include <windowsx.h>

#include <algorithm>
#include <array>
#include <memory>
#include <string>

#include <nlohmann/json.hpp>

#include "../resources/resource.h"
#include "ui_theme.h"
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

bool Win32Shell::Create(const std::wstring& title, int width, int height) {
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
  hwnd_ = CreateWindowExW(0, window_class.lpszClassName, title.c_str(), style, CW_USEDEFAULT,
                          CW_USEDEFAULT, width, height, nullptr, nullptr, instance_, this);
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

LRESULT Win32Shell::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_CREATE: {
      window_chrome_.Attach(hwnd_, instance_);
      const ACCEL shortcuts[] = {{FVIRTKEY | FCONTROL, 'T', IDM_NEW_TAB}, {FVIRTKEY | FCONTROL, 'W', IDM_CLOSE_TAB},
                                 {FVIRTKEY | FCONTROL, 'L', IDM_FOCUS_URL}, {FVIRTKEY | FCONTROL, VK_TAB, IDM_NEXT_TAB},
                                 {FVIRTKEY | FCONTROL | FSHIFT, VK_TAB, IDM_PREVIOUS_TAB}};
      accelerators_ = CreateAcceleratorTableW(const_cast<LPACCEL>(shortcuts), static_cast<int>(std::size(shortcuts)));
      RECT rect{};
      GetClientRect(hwnd_, &rect);
      tab_strip_ = CreateWindowExW(0, WC_TABCONTROLW, L"", WS_CHILD | WS_VISIBLE | WS_TABSTOP | TCS_TABS | TCS_OWNERDRAWFIXED,
                                   0, 0, 0, 0, hwnd_, reinterpret_cast<HMENU>(IDC_TAB_STRIP), instance_, nullptr);
      new_tab_button_ = CreateWindowExW(0, L"BUTTON", L"New tab", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
                                        0, 0, 0, 0, hwnd_, reinterpret_cast<HMENU>(IDC_NEW_TAB_BUTTON), instance_, nullptr);
      url_bar_.Create(hwnd_, instance_, rect, delegate_);
      browser_view_->Create(hwnd_, instance_, rect, observer_);
      toast_.Create(hwnd_, instance_);
      bookmarks_view_.SetNavigateCallback([this](const std::string& url) { delegate_->OnNavigateRequested(url); });
      history_view_.SetNavigateCallback([this](const std::string& url) { delegate_->OnNavigateRequested(url); });
      LayoutChildren(rect.right, rect.bottom);
      RefreshTabs();
      return 0;
    }
    case WM_NCCALCSIZE:
      if (wparam == TRUE) return 0;
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
      return 0;
    }
    case WM_ACTIVATE: window_chrome_.SetActive(LOWORD(wparam) != WA_INACTIVE); break;
    case WM_MOUSEMOVE: {
      window_chrome_.TrackMouse({GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)});
      break;
    }
    case WM_MOUSELEAVE: window_chrome_.TrackMouseLeave(); return 0;
    case WM_PAINT: {
      PAINTSTRUCT paint{};
      HDC dc = BeginPaint(hwnd_, &paint);
      window_chrome_.Draw(dc);
      url_bar_.Paint(dc);
      EndPaint(hwnd_, &paint);
      return 0;
    }
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
    case WM_HSCROLL:
      if (reinterpret_cast<HWND>(lparam) == tab_strip_) LayoutTabCloseButtons();
      break;
    case WM_COMMAND: {
      const UINT id = LOWORD(wparam);
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
        case IDC_BACK_BUTTON: delegate_->OnBackRequested(); return 0;
        case IDC_FORWARD_BUTTON: delegate_->OnForwardRequested(); return 0;
        case IDC_RELOAD_BUTTON: delegate_->OnReloadRequested(); return 0;
        case IDC_BOOKMARKS_BUTTON: ShowPanel(IDM_VIEW_BOOKMARKS); return 0;
        case IDC_HISTORY_BUTTON: ShowPanel(IDM_VIEW_HISTORY); return 0;
        case IDC_NETWORK_BUTTON: ShowPanel(IDM_VIEW_NETWORK); return 0;
        case IDC_SETTINGS_BUTTON:
        case IDM_SETTINGS: delegate_->OnOpenSettingsRequested(); return 0;
        case IDC_NEW_TAB_BUTTON:
        case IDM_NEW_TAB: delegate_->OnCreateTabRequested(); return 0;
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

void Win32Shell::LayoutChildren(int width, int height) {
  window_chrome_.LayoutControls();
  const int inset = window_chrome_.Inset();
  const int title = window_chrome_.TitleBarHeight();
  RECT toolbar{inset, title, width - inset, height - inset};
  url_bar_.Resize(toolbar);
  const int tab_top = title + url_bar_.Height();
  const int tab_height = ui::Dip(hwnd_, 34);
  const int padding = ui::Dip(hwnd_, 12);
  const int new_width = ui::Dip(hwnd_, 34);
  SetWindowPos(tab_strip_, nullptr, inset + padding, tab_top, std::max(ui::Dip(hwnd_, 120), width - (2 * padding) - new_width - inset), tab_height, SWP_NOZORDER);
  SetWindowPos(new_tab_button_, nullptr, width - inset - padding - new_width, tab_top, new_width, tab_height, SWP_NOZORDER);
  TabCtrl_SetItemSize(tab_strip_, ui::Dip(hwnd_, 160), tab_height - ui::Dip(hwnd_, 2));
  LayoutTabCloseButtons();
  RECT browser{inset, tab_top + tab_height, width - inset, height - inset};
  browser_view_->Resize(browser);
  toast_.Resize(browser);
  InvalidateRect(hwnd_, nullptr, FALSE);
}

bool Win32Shell::RefreshTabs() {
  if (tab_strip_ == nullptr || delegate_ == nullptr) return false;
  const nlohmann::json parsed = nlohmann::json::parse(delegate_->GetTabsJson(), nullptr, false);
  const nlohmann::json* entries = parsed.is_object() && parsed.contains("tabs") ? &parsed["tabs"] : &parsed;
  if (!entries->is_array()) return false;
  std::vector<TabItem> next;
  std::string active;
  for (const auto& entry : *entries) {
    if (!entry.is_object()) continue;
    const std::string id = entry.value("id", "");
    if (id.empty()) continue;
    std::string label = entry.value("title", "");
    if (label.empty()) label = entry.value("url", "");
    if (label.empty()) label = "New tab";
    const bool selected = entry.value("active", false);
    next.push_back({id, entry.value("generation", std::uint64_t{0}), label, selected});
    if (selected) active = id;
  }
  if (SameTabs(tabs_, next) && active_tab_id_ == active) return false;
  const bool active_changed = active_tab_id_ != active;
  tabs_ = std::move(next);
  active_tab_id_ = active;
  TabCtrl_DeleteAllItems(tab_strip_);
  int selected = -1;
  for (std::size_t index = 0; index < tabs_.size(); ++index) {
    std::wstring text = utf::Utf8ToWideDisplay(tabs_[index].label);
    TCITEMW item{};
    item.mask = TCIF_TEXT;
    item.pszText = text.data();
    TabCtrl_InsertItem(tab_strip_, static_cast<int>(index), &item);
    if (tabs_[index].active) selected = static_cast<int>(index);
  }
  TabCtrl_SetCurSel(tab_strip_, selected >= 0 ? selected : 0);
  RebuildTabCloseButtons();
  return active_changed;
}

void Win32Shell::RebuildTabCloseButtons() {
  for (const auto& button : tab_close_buttons_) if (button.hwnd != nullptr) DestroyWindow(button.hwnd);
  tab_close_buttons_.clear();
  for (std::size_t index = 0; index < tabs_.size() && index < 256; ++index) {
    const auto& tab = tabs_[index];
    const std::wstring title = utf::Utf8ToWideDisplay(tab.label);
    HWND button = CreateWindowExW(0, L"BUTTON", (L"Close " + title).c_str(), WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
                                  0, 0, 0, 0, hwnd_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kTabCloseFirst + index)), instance_, nullptr);
    tab_close_buttons_.push_back({button, tab.id, tab.generation});
  }
  RECT rect{};
  GetClientRect(hwnd_, &rect);
  LayoutChildren(rect.right, rect.bottom);
}

void Win32Shell::LayoutTabCloseButtons() {
  RECT strip{};
  GetClientRect(tab_strip_, &strip);
  MapWindowPoints(tab_strip_, hwnd_, reinterpret_cast<POINT*>(&strip), 2);
  for (std::size_t index = 0; index < tab_close_buttons_.size(); ++index) {
    RECT item{};
    if (!TabCtrl_GetItemRect(tab_strip_, static_cast<int>(index), &item)) {
      ShowWindow(tab_close_buttons_[index].hwnd, SW_HIDE);
      continue;
    }
    MapWindowPoints(tab_strip_, hwnd_, reinterpret_cast<POINT*>(&item), 2);
    const int size = ui::Dip(hwnd_, 18);
    const int left = item.right - size - ui::Dip(hwnd_, 5);
    const bool visible = left >= strip.left && left + size <= strip.right &&
                         item.top >= strip.top && item.bottom <= strip.bottom;
    if (!visible) {
      ShowWindow(tab_close_buttons_[index].hwnd, SW_HIDE);
      continue;
    }
    SetWindowPos(tab_close_buttons_[index].hwnd, HWND_TOP, item.right - size - ui::Dip(hwnd_, 5),
                 item.top + (item.bottom - item.top - size) / 2, size, size,
                 SWP_NOACTIVATE | SWP_SHOWWINDOW);
  }
}

bool Win32Shell::DrawControl(const DRAWITEMSTRUCT& item) const {
  if (window_chrome_.DrawControl(item) || url_bar_.DrawControl(item)) return true;
  const auto colors = ui::Colors();
  if (item.CtlID == IDC_NEW_TAB_BUTTON) {
    ui::PaintRounded(item.hDC, item.rcItem, colors.surface, colors.border, ui::Dip(hwnd_, 8));
    ui::DrawGlyph(item.hDC, hwnd_, item.rcItem, L'+', colors.text);
    return true;
  }
  if (IsTabClose(item.CtlID)) {
    const bool pressed = (item.itemState & ODS_SELECTED) != 0;
    ui::PaintRounded(item.hDC, item.rcItem, pressed ? colors.surface_hover : colors.surface, colors.border, ui::Dip(hwnd_, 4));
    ui::DrawGlyph(item.hDC, hwnd_, item.rcItem, L'×', colors.muted_text, 12);
    return true;
  }
  if (item.CtlID != IDC_TAB_STRIP || item.itemID >= tabs_.size()) return false;
  const TabItem& tab = tabs_[item.itemID];
  const bool selected = tab.active || (item.itemState & ODS_SELECTED) != 0;
  const COLORREF selected_fill = ui::HighContrast() ? GetSysColor(COLOR_HIGHLIGHT) : RGB(237, 243, 254);
  ui::PaintRounded(item.hDC, item.rcItem, selected ? selected_fill : colors.canvas,
                   selected ? colors.focus : colors.border, ui::Dip(hwnd_, 8));
  RECT text = item.rcItem;
  text.left += ui::Dip(hwnd_, 10);
  text.right -= ui::Dip(hwnd_, 28);
  HFONT font = ui::MakeFont(hwnd_, 12, FW_NORMAL);
  HGDIOBJ old = SelectObject(item.hDC, font);
  SetBkMode(item.hDC, TRANSPARENT);
  SetTextColor(item.hDC, ui::HighContrast() && selected ? GetSysColor(COLOR_HIGHLIGHTTEXT) :
               (selected ? colors.text : colors.muted_text));
  const std::wstring title = utf::Utf8ToWideDisplay(tab.label);
  DrawTextW(item.hDC, title.c_str(), -1, &text, DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX);
  SelectObject(item.hDC, old);
  DeleteObject(font);
  return true;
}

bool Win32Shell::SameTabs(const std::vector<TabItem>& left, const std::vector<TabItem>& right) {
  if (left.size() != right.size()) return false;
  for (std::size_t index = 0; index < left.size(); ++index) {
    if (left[index].id != right[index].id || left[index].generation != right[index].generation ||
        left[index].label != right[index].label || left[index].active != right[index].active) return false;
  }
  return true;
}

void Win32Shell::ActivateAdjacentTab(int direction) {
  if (tabs_.empty()) return;
  const int current = std::max(0, TabCtrl_GetCurSel(tab_strip_));
  TabCtrl_SetCurSel(tab_strip_, (current + direction + static_cast<int>(tabs_.size())) % static_cast<int>(tabs_.size()));
  ActivateSelectedTab();
}

void Win32Shell::ActivateSelectedTab() {
  const int selected = TabCtrl_GetCurSel(tab_strip_);
  if (selected >= 0 && static_cast<std::size_t>(selected) < tabs_.size()) {
    const auto& tab = tabs_[selected];
    delegate_->OnActivateTabRequested(tab.id, tab.generation);
    browser_view_->Focus();
  }
}

void Win32Shell::CloseTabAt(std::size_t index) {
  if (index < tabs_.size()) delegate_->OnCloseTabRequested(tabs_[index].id, tabs_[index].generation);
}

std::vector<HWND> Win32Shell::FocusOrder() const {
  std::vector<HWND> controls = window_chrome_.FocusableControls();
  const std::vector<HWND> toolbar = url_bar_.FocusableControls();
  controls.insert(controls.end(), toolbar.begin(), toolbar.end());
  if (tab_strip_ != nullptr && IsWindowVisible(tab_strip_) && IsWindowEnabled(tab_strip_)) controls.push_back(tab_strip_);
  for (const TabCloseButton& button : tab_close_buttons_) {
    if (button.hwnd != nullptr && IsWindowVisible(button.hwnd) && IsWindowEnabled(button.hwnd)) controls.push_back(button.hwnd);
  }
  if (new_tab_button_ != nullptr && IsWindowVisible(new_tab_button_) && IsWindowEnabled(new_tab_button_)) controls.push_back(new_tab_button_);
  return controls;
}

}  // namespace kelpie::windows
