#include "url_bar.h"

#include <commctrl.h>

#include <algorithm>

#include "../resources/resource.h"
#include "theme/theme.h"
#include "url_completion.h"
#include "windows_utf.h"

namespace kelpie::windows {
namespace {

std::wstring ReadWindowText(HWND hwnd) {
  const int length = GetWindowTextLengthW(hwnd);
  if (length <= 0) return {};
  std::wstring value(static_cast<std::size_t>(length) + 1, L'\0');
  const int copied = GetWindowTextW(hwnd, value.data(), static_cast<int>(value.size()));
  value.resize(copied > 0 ? static_cast<std::size_t>(copied) : 0);
  return value;
}

bool IsIconButton(UINT id) {
  return id == IDC_BACK_BUTTON || id == IDC_FORWARD_BUTTON || id == IDC_RELOAD_BUTTON ||
         id == IDC_BOOKMARKS_BUTTON || id == IDC_HISTORY_BUTTON || id == IDC_NETWORK_BUTTON ||
         id == IDC_SETTINGS_BUTTON || id == IDC_HOME_BUTTON || id == IDC_ACCOUNT_BUTTON || id == IDC_ADD_FAVORITE_BUTTON;
}

wchar_t IconFor(UINT id, bool loading) {
  switch (id) {
    case IDC_HOME_BUTTON: return L'';
    case IDC_ADD_FAVORITE_BUTTON: return ui::icon::kBookmarks;
    case IDC_BACK_BUTTON: return ui::icon::kBack;
    case IDC_FORWARD_BUTTON: return ui::icon::kForward;
    case IDC_RELOAD_BUTTON: return loading ? ui::icon::kStop : ui::icon::kReload;
    case IDC_BOOKMARKS_BUTTON: return L'\ue80a';
    case IDC_HISTORY_BUTTON: return ui::icon::kHistory;
    case IDC_NETWORK_BUTTON: return ui::icon::kNetwork;
    default: return L'';
  }
}

// Show the transport lock only for secure URLs.
bool IsSecureUrl(const std::wstring& url) {
  return url.rfind(L"https://", 0) == 0;
}

}  // namespace

bool UrlBar::Create(HWND parent, HINSTANCE instance, const RECT& bounds, UrlBarDelegate* delegate) {
  parent_ = parent;
  delegate_ = delegate;
  const auto make_button = [&](int id, const wchar_t* name, HWND* result) {
    *result = CreateWindowExW(0, L"BUTTON", name, WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
                              0, 0, 0, 0, parent, reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), instance, nullptr);
    if (*result != nullptr) {
      SetWindowSubclass(*result, &UrlBar::ButtonProc, static_cast<UINT_PTR>(id),
                        reinterpret_cast<DWORD_PTR>(this));
    }
    return *result != nullptr;
  };
  if (!make_button(IDC_BACK_BUTTON, L"Back", &back_button_) ||
      !make_button(IDC_FORWARD_BUTTON, L"Forward", &forward_button_) ||
      !make_button(IDC_RELOAD_BUTTON, L"Reload", &reload_button_) ||
      !make_button(IDC_HOME_BUTTON, L"Home", &home_button_) ||
      !make_button(IDC_ADD_FAVORITE_BUTTON, L"Add favorite", &add_favorite_button_) ||
      !make_button(IDC_BOOKMARKS_BUTTON, L"Bookmarks", &bookmarks_button_) ||
      !make_button(IDC_HISTORY_BUTTON, L"History", &history_button_) ||
      !make_button(IDC_NETWORK_BUTTON, L"Network Inspector", &network_button_) ||
      !make_button(IDC_ACCOUNT_BUTTON, L"UOA account", &account_button_) ||
      !make_button(IDC_SETTINGS_BUTTON, L"Settings", &settings_button_)) return false;
  url_edit_ = CreateWindowExW(0, L"EDIT", L"", WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_AUTOHSCROLL,
                              0, 0, 0, 0, parent, reinterpret_cast<HMENU>(IDC_URL_EDIT), instance, nullptr);
  if (url_edit_ == nullptr) return false;
  tooltip_ = CreateWindowExW(WS_EX_TOPMOST, TOOLTIPS_CLASSW, nullptr,
                             WS_POPUP | TTS_ALWAYSTIP, 0, 0, 0, 0, parent,
                             nullptr, instance, nullptr);
  if (tooltip_ != nullptr) {
    const auto add_tooltip = [&](HWND control, const wchar_t* text) {
      TOOLINFOW tool{sizeof(tool)};
      tool.uFlags = TTF_SUBCLASS | TTF_IDISHWND;
      tool.hwnd = parent;
      tool.uId = reinterpret_cast<UINT_PTR>(control);
      tool.lpszText = const_cast<wchar_t*>(text);
      SendMessageW(tooltip_, TTM_ADDTOOLW, 0, reinterpret_cast<LPARAM>(&tool));
    };
    add_tooltip(account_button_, L"UnlikeOtherAI account");
    add_tooltip(home_button_, L"Home");
    add_tooltip(add_favorite_button_, L"Add current page to favorites");
    add_tooltip(back_button_, L"Back");
    add_tooltip(forward_button_, L"Forward");
    add_tooltip(reload_button_, L"Reload or stop loading");
    add_tooltip(bookmarks_button_, L"Bookmarks");
    add_tooltip(history_button_, L"History");
    add_tooltip(network_button_, L"Network inspector");
    add_tooltip(settings_button_, L"Settings");
  }
  SetWindowLongPtrW(url_edit_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));
  original_edit_proc_ = reinterpret_cast<WNDPROC>(SetWindowLongPtrW(
      url_edit_, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(&UrlBar::EditProc)));
  // The lock's width is reserved by the gutter in Resize whether or not the
  // glyph is drawn, so the text does not shift when the scheme changes.
  SendMessageW(url_edit_, EM_SETMARGINS, EC_LEFTMARGIN | EC_RIGHTMARGIN,
               MAKELPARAM(ui::Dip(parent, 2), ui::Dip(parent, 8)));
  SendMessageW(url_edit_, EM_SETCUEBANNER, TRUE,
               reinterpret_cast<LPARAM>(L"Search or enter website name"));
  RefreshFont();
  Resize(bounds);
  return true;
}

int UrlBar::Height() const { return ui::Dip(parent_, 72); }

void UrlBar::Resize(const RECT& bounds) {
  const int control_height = ui::Dip(parent_, 44);
  const int button_width = ui::Dip(parent_, 40);
  const int gap = ui::Dip(parent_, 8);
  const int padding = ui::Dip(parent_, 12);
  const int top = bounds.top + ui::Dip(parent_, 14);
  int left = bounds.left + padding;
  for (HWND button : {back_button_, forward_button_, reload_button_, home_button_}) {
    SetWindowPos(button, nullptr, left, top, button_width, control_height, SWP_NOZORDER);
    left += button_width + gap;
  }
  const int edit_right = bounds.right - padding - 5 * (button_width + gap);
  surface_ = {left, top, edit_right, top + control_height};
  const int edit_height = ui::Dip(parent_, 24);
  SetWindowPos(url_edit_, nullptr, left + ui::Dip(parent_, 48), top + (control_height-edit_height)/2,
      std::max(1, edit_right - left - ui::Dip(parent_, 96)), edit_height, SWP_NOZORDER);
  SetWindowPos(add_favorite_button_, nullptr, edit_right-ui::Dip(parent_, 46), top+ui::Dip(parent_, 5),
      ui::Dip(parent_, 34), ui::Dip(parent_, 34), SWP_NOZORDER);
  left = edit_right + gap;
  for (HWND button : {bookmarks_button_, network_button_, history_button_, account_button_, settings_button_}) {
    SetWindowPos(button, nullptr, left, top, button_width, control_height, SWP_NOZORDER);
    left += button_width + gap;
  }
  InvalidateSurface();
}

std::vector<HWND> UrlBar::FocusableControls() const {
  std::vector<HWND> controls;
  for (HWND control : {back_button_, forward_button_, reload_button_, home_button_, url_edit_, add_favorite_button_, bookmarks_button_,
                       history_button_, network_button_, account_button_, settings_button_}) {
    if (control != nullptr && IsWindowVisible(control) && IsWindowEnabled(control)) controls.push_back(control);
  }
  return controls;
}

void UrlBar::Destroy() {
  if (account_avatar_) DeleteObject(account_avatar_);
  account_avatar_ = nullptr;
  if (edit_brush_ != nullptr) DeleteObject(edit_brush_);
  if (edit_font_ != nullptr) DeleteObject(edit_font_);
  edit_brush_ = nullptr;
  edit_font_ = nullptr;
}

void UrlBar::RefreshFont() {
  if (url_edit_ == nullptr) return;
  // Keep the address readable at the reference navigation-row size.
  HFONT next = ui::MakeFont(parent_, 16, FW_NORMAL);
  if (next == nullptr) return;
  SendMessageW(url_edit_, WM_SETFONT, reinterpret_cast<WPARAM>(next), TRUE);
  if (edit_font_ != nullptr) DeleteObject(edit_font_);
  edit_font_ = next;
}

void UrlBar::SetPalette(ui::ChromePalette palette) { palette_ = palette; }

void UrlBar::RefreshTheme() {
  RefreshFont();
  // The EDIT draws its own selection highlight and caret from the system
  // theme, so it needs the dark variant explicitly.
  ui::ApplyControlAppearance(url_edit_);
  if (parent_ != nullptr) InvalidateSurface();
}

void UrlBar::SetUrl(const std::wstring& url, bool force) {
  if (url_edit_ == nullptr) return;
  if (secure_ != IsSecureUrl(url)) {
    secure_ = IsSecureUrl(url);
    InvalidateSurface();
  }
  if (!force && GetFocus() == url_edit_) return;
  setting_url_ = true;
  completion_active_ = false;
  insertion_at_end_ = false;
  completion_prefix_.clear();
  completion_navigation_url_.clear();
  SetWindowTextW(url_edit_, url.c_str());
  setting_url_ = false;
}

void UrlBar::SetNavigationState(bool can_go_back, bool can_go_forward, bool is_loading) {
  EnableWindow(back_button_, can_go_back ? TRUE : FALSE);
  EnableWindow(forward_button_, can_go_forward ? TRUE : FALSE);
  SetWindowTextW(reload_button_, is_loading ? L"Stop loading" : L"Reload");
  SetWindowLongPtrW(reload_button_, GWLP_USERDATA, is_loading ? 1 : 0);
  InvalidateRect(reload_button_, nullptr, FALSE);
}

void UrlBar::Focus() {
  completion_active_ = false;
  SetFocus(url_edit_);
  SendMessageW(url_edit_, EM_SETSEL, 0, -1);
}

bool UrlBar::HandleCommand(WORD control_id, WORD notification_code) {
  if (control_id != IDC_URL_EDIT || notification_code != EN_CHANGE || setting_url_) return false;
  CompleteAfterInsertion();
  return true;
}

bool UrlBar::DrawControl(const DRAWITEMSTRUCT& item) const {
  if (item.CtlID == IDC_ACCOUNT_BUTTON) { DrawAccount(item); return true; }
  if (!IsIconButton(item.CtlID)) return false;
  const bool disabled = (item.itemState & ODS_DISABLED) != 0;
  const bool pressed = (item.itemState & ODS_SELECTED) != 0;
  const bool focused = (item.itemState & ODS_FOCUS) != 0;
  const bool hovered = item.hwndItem == hovered_button_;
  const auto base = item.CtlID == IDC_ADD_FAVORITE_BUTTON ? palette_.field : palette_.bar;
  ui::FillSolid(item.hDC, item.rcItem, base);
  if (pressed || hovered || focused) ui::PaintRounded(item.hDC, item.rcItem, palette_.hover,
      focused ? ui::Colors().focus : palette_.hover, ui::Dip(parent_, 8), focused ? 2 : 0);
  const bool loading = item.CtlID == IDC_RELOAD_BUTTON && GetWindowLongPtrW(item.hwndItem, GWLP_USERDATA) != 0;
  ui::DrawGlyph(item.hDC, parent_, item.rcItem, IconFor(item.CtlID, loading),
                 disabled ? palette_.muted : palette_.text, 20);
  return true;
}

LRESULT CALLBACK UrlBar::ButtonProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam,
                                    UINT_PTR subclass_id, DWORD_PTR reference_data) {
  auto* self = reinterpret_cast<UrlBar*>(reference_data);
  if (self != nullptr && message == WM_MOUSEMOVE && self->hovered_button_ != hwnd) {
    self->SetHoveredButton(hwnd);
    TRACKMOUSEEVENT tracking{sizeof(tracking), TME_LEAVE, hwnd, 0};
    TrackMouseEvent(&tracking);
  } else if (self != nullptr && message == WM_MOUSELEAVE) {
    self->SetHoveredButton(nullptr);
  } else if (message == WM_NCDESTROY) {
    RemoveWindowSubclass(hwnd, &UrlBar::ButtonProc, subclass_id);
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

void UrlBar::SetHoveredButton(HWND button) {
  if (hovered_button_ == button) return;
  HWND previous = hovered_button_;
  hovered_button_ = button;
  // Redraw only the two controls whose appearance actually changed.
  if (previous != nullptr) InvalidateRect(previous, nullptr, FALSE);
  if (button != nullptr) InvalidateRect(button, nullptr, FALSE);
}

bool UrlBar::ControlColor(HDC device_context, HWND control, HBRUSH* brush) const {
  if (control != url_edit_) return false;
  SetTextColor(device_context, palette_.text);
  SetBkColor(device_context, palette_.field);
  if (!edit_brush_ || brush_color_ != palette_.field) {
    if (edit_brush_) DeleteObject(edit_brush_);
    edit_brush_ = CreateSolidBrush(palette_.field);
    brush_color_ = palette_.field;
  }
  *brush = edit_brush_;
  return true;
}

void UrlBar::Paint(HDC device_context) const {
  if (url_edit_ == nullptr) return;
  const bool focused = GetFocus() == url_edit_;
  ui::PaintRounded(device_context, surface_, palette_.field,
      focused ? ui::Colors().focus : ui::Blend(palette_.text, palette_.bar, 0.12),
      ui::Dip(parent_, 22), focused ? 2 : 1);
  if (secure_) {
    const RECT lock{surface_.left+ui::Dip(parent_, 12), surface_.top,
                    surface_.left+ui::Dip(parent_, 42), surface_.bottom};
    ui::DrawGlyph(device_context, parent_, lock, ui::icon::kLock,
        ui::HighContrast() ? palette_.text : ui::IsDark(palette_.bar) ? RGB(92,220,130) : RGB(25,154,52), 17);
  }
}

void UrlBar::InvalidateSurface() const {
  if (parent_ != nullptr) InvalidateRect(parent_, nullptr, FALSE);
}

LRESULT CALLBACK UrlBar::EditProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<UrlBar*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (self == nullptr) return DefWindowProcW(hwnd, message, wparam, lparam);
  if (message == WM_CHAR) {
    const std::wstring before = ReadWindowText(hwnd);
    DWORD start = 0;
    DWORD end = 0;
    SendMessageW(hwnd, EM_GETSEL, reinterpret_cast<WPARAM>(&start), reinterpret_cast<LPARAM>(&end));
    self->insertion_at_end_ = completion::IsTextInsertionAtEnd(
        self->ime_composing_, before.size(), start, end, static_cast<wchar_t>(wparam));
    self->completion_active_ = false;
    self->completion_navigation_url_.clear();
  } else if (message == WM_PASTE || message == WM_CUT || message == WM_CLEAR || message == WM_UNDO || message == WM_IME_STARTCOMPOSITION) {
    self->insertion_at_end_ = false;
    self->completion_active_ = false;
    self->completion_navigation_url_.clear();
    if (message == WM_IME_STARTCOMPOSITION) self->ime_composing_ = true;
  } else if (message == WM_IME_ENDCOMPOSITION) {
    self->ime_composing_ = false;
  } else if (message == WM_KEYDOWN) {
    if (wparam == VK_ESCAPE && self->completion_active_) { self->RejectCompletion(); return 0; }
    if (wparam == VK_RETURN) {
      const std::optional<std::wstring_view> completion_url = self->completion_active_
          ? std::optional<std::wstring_view>(self->completion_navigation_url_) : std::nullopt;
      if (self->completion_active_) SendMessageW(hwnd, EM_SETSEL, -1, -1);
      self->completion_active_ = false;
      self->SubmitCurrentUrl(completion_url);
      return 0;
    }
    self->completion_active_ = false;
    self->completion_navigation_url_.clear();
    if (wparam == VK_BACK || wparam == VK_DELETE) self->insertion_at_end_ = false;
  } else if (message == WM_LBUTTONDOWN || message == WM_RBUTTONDOWN || message == WM_MOUSEWHEEL) {
    self->completion_active_ = false;
    self->completion_navigation_url_.clear();
  } else if (message == WM_SETFOCUS || message == WM_KILLFOCUS) {
    self->InvalidateSurface();
  }
  return CallWindowProcW(self->original_edit_proc_, hwnd, message, wparam, lparam);
}

void UrlBar::CompleteAfterInsertion() {
  if (!insertion_at_end_) return;
  insertion_at_end_ = false;
  const std::wstring typed = ReadWindowText(url_edit_);
  const auto candidate = delegate_ == nullptr ? std::nullopt : delegate_->BestUrlCompletion(typed);
  if (!candidate) return;
  const auto display = completion::DisplayCandidate(typed, *candidate);
  if (!display) return;
  setting_url_ = true;
  SetWindowTextW(url_edit_, display->c_str());
  SendMessageW(url_edit_, EM_SETSEL, static_cast<WPARAM>(typed.size()), static_cast<LPARAM>(display->size()));
  setting_url_ = false;
  completion_prefix_ = typed;
  completion_navigation_url_ = *candidate;
  completion_active_ = true;
}

void UrlBar::RejectCompletion() {
  setting_url_ = true;
  SetWindowTextW(url_edit_, completion_prefix_.c_str());
  SendMessageW(url_edit_, EM_SETSEL, -1, -1);
  setting_url_ = false;
  completion_active_ = false;
  completion_navigation_url_.clear();
}

void UrlBar::SubmitCurrentUrl(std::optional<std::wstring_view> completion_url) {
  if (delegate_ == nullptr || url_edit_ == nullptr) return;
  const auto url = utf::WideToUtf8(completion_url.value_or(ReadWindowText(url_edit_)));
  if (url && !url->empty()) delegate_->OnNavigateRequested(*url);
}

}  // namespace kelpie::windows
