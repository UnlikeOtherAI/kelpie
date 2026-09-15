#include "win32_shell.h"

#include <commctrl.h>

#include <memory>
#include <iterator>
#include <string>

#include <nlohmann/json.hpp>

#include "../resources/resource.h"
#include "windows_utf.h"

namespace kelpie::windows {
namespace {

constexpr UINT kToastMessage = WM_APP + 1;
constexpr UINT_PTR kToastTimerId = 1;
constexpr int kTabHeight = 30;

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
  window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  RegisterClassExW(&window_class);
  hwnd_ = CreateWindowExW(0, window_class.lpszClassName, title.c_str(),
                          WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN | WS_CLIPSIBLINGS,
                          CW_USEDEFAULT, CW_USEDEFAULT, width, height, nullptr, nullptr, instance_, this);
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
  url_bar_.SetNavigationState(state.can_go_back, state.can_go_forward, state.is_loading);
  if (!state.title.empty()) {
    SetWindowTextW(hwnd_, (utf::Utf8ToWideDisplay(state.title) + L" - Kelpie").c_str());
  }
}

void Win32Shell::ShowToast(const std::wstring& message) {
  if (hwnd_ != nullptr) PostMessageW(hwnd_, kToastMessage, 0, reinterpret_cast<LPARAM>(new std::wstring(message)));
}

void Win32Shell::Close() { if (hwnd_ != nullptr) DestroyWindow(hwnd_); }

LRESULT CALLBACK Win32Shell::WindowProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<Win32Shell*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    self = reinterpret_cast<Win32Shell*>(create->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    self->hwnd_ = hwnd;
  }
  return self != nullptr ? self->HandleMessage(message, wparam, lparam) : DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT Win32Shell::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_CREATE: {
      CreateMenuBar();
      const ACCEL shortcuts[] = {
          {FVIRTKEY | FCONTROL, 'T', IDM_NEW_TAB}, {FVIRTKEY | FCONTROL, 'W', IDM_CLOSE_TAB},
          {FVIRTKEY | FCONTROL, 'L', IDM_FOCUS_URL}, {FVIRTKEY | FCONTROL, VK_TAB, IDM_NEXT_TAB},
          {FVIRTKEY | FCONTROL | FSHIFT, VK_TAB, IDM_PREVIOUS_TAB},
      };
      accelerators_ = CreateAcceleratorTableW(const_cast<LPACCEL>(shortcuts), static_cast<int>(std::size(shortcuts)));
      RECT rect{};
      GetClientRect(hwnd_, &rect);
      tab_strip_ = CreateWindowExW(0, WC_TABCONTROLW, L"", WS_CHILD | WS_VISIBLE | TCS_TABS | TCS_FOCUSNEVER,
                                   8, 2, 300, kTabHeight, hwnd_, reinterpret_cast<HMENU>(IDC_TAB_STRIP), instance_, nullptr);
      new_tab_button_ = CreateWindowExW(0, L"BUTTON", L"+", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                        0, 0, 28, 26, hwnd_, reinterpret_cast<HMENU>(IDC_NEW_TAB_BUTTON), instance_, nullptr);
      close_tab_button_ = CreateWindowExW(0, L"BUTTON", L"x", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                          0, 0, 28, 26, hwnd_, reinterpret_cast<HMENU>(IDC_CLOSE_TAB_BUTTON), instance_, nullptr);
      url_bar_.Create(hwnd_, instance_, rect, delegate_);
      browser_view_->Create(hwnd_, instance_, rect, observer_);
      toast_.Create(hwnd_, instance_);
      bookmarks_view_.SetNavigateCallback([this](const std::string& url) { delegate_->OnNavigateRequested(url); });
      history_view_.SetNavigateCallback([this](const std::string& url) { delegate_->OnNavigateRequested(url); });
      LayoutChildren(rect.right, rect.bottom);
      RefreshTabs();
      return 0;
    }
    case WM_SIZE:
      LayoutChildren(LOWORD(lparam), HIWORD(lparam));
      return 0;
    case WM_NOTIFY:
      if (reinterpret_cast<NMHDR*>(lparam)->idFrom == IDC_TAB_STRIP && reinterpret_cast<NMHDR*>(lparam)->code == TCN_SELCHANGE) {
        ActivateSelectedTab();
        return 0;
      }
      break;
    case WM_COMMAND:
      if (url_bar_.HandleCommand(LOWORD(wparam), HIWORD(wparam))) return 0;
      switch (LOWORD(wparam)) {
        case IDC_BACK_BUTTON: delegate_->OnBackRequested(); return 0;
        case IDC_FORWARD_BUTTON: delegate_->OnForwardRequested(); return 0;
        case IDC_RELOAD_BUTTON: delegate_->OnReloadRequested(); return 0;
        case IDC_NEW_TAB_BUTTON:
        case IDM_NEW_TAB: delegate_->OnCreateTabRequested(); return 0;
        case IDC_CLOSE_TAB_BUTTON:
        case IDM_CLOSE_TAB: CloseSelectedTab(); return 0;
        case IDM_FOCUS_URL: url_bar_.Focus(); return 0;
        case IDM_NEXT_TAB: ActivateAdjacentTab(1); return 0;
        case IDM_PREVIOUS_TAB: ActivateAdjacentTab(-1); return 0;
        case IDC_SETTINGS_BUTTON:
        case IDM_SETTINGS: delegate_->OnOpenSettingsRequested(); return 0;
        case IDM_VIEW_BOOKMARKS:
          bookmarks_view_.EnsureCreated(instance_, hwnd_);
          bookmarks_view_.UpdateFromJson(delegate_->GetBookmarksJson());
          bookmarks_view_.ToggleVisible(); return 0;
        case IDM_VIEW_HISTORY:
          history_view_.EnsureCreated(instance_, hwnd_);
          history_view_.UpdateFromJson(delegate_->GetHistoryJson());
          history_view_.ToggleVisible(); return 0;
        case IDM_VIEW_NETWORK:
          network_view_.EnsureCreated(instance_, hwnd_);
          network_view_.UpdateFromJson(delegate_->GetNetworkJson());
          network_view_.ToggleVisible(); return 0;
        default: break;
      }
      break;
    case WM_SETFOCUS:
      browser_view_->Focus();
      return 0;
    case WM_TIMER:
      if (wparam == kToastTimerId) { KillTimer(hwnd_, kToastTimerId); toast_.Hide(); return 0; }
      break;
    case kToastMessage: {
      std::unique_ptr<std::wstring> payload(reinterpret_cast<std::wstring*>(lparam));
      if (payload) {
        toast_.ShowMessage(*payload);
        KillTimer(hwnd_, kToastTimerId);
        SetTimer(hwnd_, kToastTimerId, 3000, nullptr);
      }
      return 0;
    }
    case WM_CLOSE:
      delegate_->OnWindowCloseRequested();
      DestroyWindow(hwnd_);
      return 0;
    case WM_DESTROY:
      if (accelerators_) { DestroyAcceleratorTable(accelerators_); accelerators_ = nullptr; }
      PostQuitMessage(0);
      return 0;
    default: break;
  }
  return DefWindowProcW(hwnd_, message, wparam, lparam);
}

void Win32Shell::CreateMenuBar() {
  HMENU menu = CreateMenu();
  HMENU view_menu = CreatePopupMenu();
  AppendMenuW(view_menu, MF_STRING, IDM_VIEW_BOOKMARKS, L"Bookmarks");
  AppendMenuW(view_menu, MF_STRING, IDM_VIEW_HISTORY, L"History");
  AppendMenuW(view_menu, MF_STRING, IDM_VIEW_NETWORK, L"Network Inspector");
  AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(view_menu), L"View");
  AppendMenuW(menu, MF_STRING, IDM_SETTINGS, L"Settings");
  SetMenu(hwnd_, menu);
}

void Win32Shell::LayoutChildren(int width, int height) {
  const int controls_right = std::max(80, width - 8);
  SetWindowPos(new_tab_button_, nullptr, controls_right - 60, 2, 28, 26, SWP_NOZORDER);
  SetWindowPos(close_tab_button_, nullptr, controls_right - 28, 2, 28, 26, SWP_NOZORDER);
  SetWindowPos(tab_strip_, nullptr, 8, 2, std::max(40, width - 80), kTabHeight, SWP_NOZORDER);
  RECT chrome{0, kTabHeight, width, height};
  url_bar_.Resize(chrome);
  RECT browser_rect{0, kTabHeight + url_bar_.Height(), width, height};
  browser_view_->Resize(browser_rect);
  toast_.Resize(RECT{0, 0, width, height});
}

bool Win32Shell::RefreshTabs() {
  if (tab_strip_ == nullptr || delegate_ == nullptr) return false;
  const nlohmann::json parsed = nlohmann::json::parse(delegate_->GetTabsJson(), nullptr, false);
  const nlohmann::json* entries = parsed.is_object() && parsed.contains("tabs") ? &parsed["tabs"] : &parsed;
  if (!entries->is_array()) return false;
  std::vector<TabItem> next_tabs;
  std::string next_active;
  for (const auto& entry : *entries) {
    if (!entry.is_object()) continue;
    const std::string id = entry.value("id", "");
    if (id.empty()) continue;
    std::string label = entry.value("title", "");
    if (label.empty()) label = entry.value("url", "");
    if (label.empty()) label = "New tab";
    const bool active = entry.value("active", false);
    next_tabs.push_back({id, entry.value("generation", std::uint64_t{0}), label, active});
    if (active) next_active = id;
  }
  if (SameTabs(tabs_, next_tabs) && active_tab_id_ == next_active) return false;

  const int previous = TabCtrl_GetCurSel(tab_strip_);
  const bool active_changed = active_tab_id_ != next_active;
  tabs_ = std::move(next_tabs);
  active_tab_id_ = next_active;
  TabCtrl_DeleteAllItems(tab_strip_);
  int active = -1;
  for (std::size_t index = 0; index < tabs_.size(); ++index) {
    const TabItem& tab = tabs_[index];
    std::wstring text = utf::Utf8ToWideDisplay(tab.label);
    TCITEMW item{};
    item.mask = TCIF_TEXT;
    item.pszText = text.data();
    TabCtrl_InsertItem(tab_strip_, static_cast<int>(index), &item);
    if (tab.active) active = static_cast<int>(index);
  }
  const int count = static_cast<int>(tabs_.size());
  TabCtrl_SetCurSel(tab_strip_, active >= 0 ? active : previous >= 0 && previous < count ? previous : 0);
  EnableWindow(close_tab_button_, count > 0 ? TRUE : FALSE);
  return active_changed;
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
  const int next = (current + direction + static_cast<int>(tabs_.size())) % static_cast<int>(tabs_.size());
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
