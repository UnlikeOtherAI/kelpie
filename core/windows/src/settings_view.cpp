#include "settings_view.h"
#include "computer_approval.h"

#include <commctrl.h>
#include <uxtheme.h>
#include <vsstyle.h>

#include <array>
#include <iterator>
#include <string>

#include "../resources/resource.h"
#include "theme/theme.h"

namespace kelpie::windows {
namespace {

constexpr int kLocalAiId = 3250;
constexpr int kTrustedComputersId = 3251;
// Static text, distinguished so WM_CTLCOLORSTATIC can give hints muted ink.
constexpr int kLabelId = 3260;
constexpr int kHintId = 3261;
constexpr int kSectionId = 3262;

constexpr DWORD kStyle = WS_POPUP | WS_CAPTION | WS_SYSMENU | WS_CLIPCHILDREN;
constexpr DWORD kExStyle = WS_EX_DLGMODALFRAME | WS_EX_CONTROLPARENT;
constexpr SIZE kClientDip{520, 392};
constexpr int kFooterDip = 64;
constexpr std::size_t kControlCount = 15;
// The start page EDIT sits inside this painted, rounded field.
constexpr RECT kUrlFieldDip{172, 54, -24, 86};

struct Control {
  int id;
  const wchar_t* kind;
  const wchar_t* text;
  DWORD style;
  RECT dip;  // left, top, right, bottom in DIP; a negative right is measured from the right edge
};

class SettingsDialogState {
 public:
  SettingsDialogState(const SettingsValues& initial, SettingsValues& output)
      : values(initial), output_ref(output) {}

  SettingsValues values;
  SettingsValues& output_ref;
  bool accepted = false;
  bool done = false;
  HWND hovered = nullptr;
  std::array<HWND, kControlCount> controls{};
  HFONT font = nullptr;
  HFONT section_font = nullptr;
  HFONT hint_font = nullptr;
  HBRUSH surface_brush = nullptr;
  std::function<void(HWND)> show_ai;
};

std::wstring WindowText(HWND hwnd) {
  const int length = GetWindowTextLengthW(hwnd);
  if (length <= 0) return {};
  std::wstring value(static_cast<std::size_t>(length) + 1, L'\0');
  const int copied = GetWindowTextW(hwnd, value.data(), static_cast<int>(value.size()));
  value.resize(copied > 0 ? static_cast<std::size_t>(copied) : 0);
  return value;
}

std::array<Control, kControlCount> Controls(const SettingsValues& values, const std::wstring& port) {
  constexpr DWORD kReadOnly = ES_AUTOHSCROLL | ES_READONLY | WS_TABSTOP;
  return {{
      {kSectionId, L"STATIC", L"Browsing", SS_LEFT, {24, 20, -24, 42}},
      {kLabelId, L"STATIC", L"Start page", SS_LEFT | SS_CENTERIMAGE, {24, 54, 160, 86}},
      {IDC_SETTINGS_STARTUP_URL, L"EDIT", values.startup_url.c_str(), ES_AUTOHSCROLL | WS_TABSTOP,
       kUrlFieldDip},
      {IDC_SETTINGS_ISOLATE_TABS, L"BUTTON", L"Isolate every new tab", BS_AUTOCHECKBOX | WS_TABSTOP,
       {168, 100, -24, 126}},
      {kHintId, L"STATIC", L"Each new tab gets its own cookies and storage, so sign-ins do not carry over.",
       SS_LEFT, {200, 128, -24, 164}},
      {kSectionId, L"STATIC", L"Launch options", SS_LEFT, {24, 196, -24, 218}},
      {kLabelId, L"STATIC", L"Control port", SS_LEFT, {24, 228, 172, 250}},
      {IDC_SETTINGS_PORT, L"EDIT", port.c_str(), kReadOnly, {183, 228, -24, 250}},
      {kLabelId, L"STATIC", L"Profile folder", SS_LEFT, {24, 256, 172, 278}},
      {IDC_SETTINGS_PROFILE, L"EDIT", values.profile_dir.c_str(), kReadOnly, {183, 256, -24, 278}},
      {kHintId, L"STATIC", L"Set when Kelpie starts, with --port and --profile-dir.", SS_LEFT,
       {183, 284, -24, 304}},
      {kTrustedComputersId, L"BUTTON", L"Trusted computers", BS_OWNERDRAW | WS_TABSTOP, {140, -48, 280, -16}},
      {kLocalAiId, L"BUTTON", L"Local AI…", BS_OWNERDRAW | WS_TABSTOP, {24, -48, 132, -16}},
      {IDCANCEL, L"BUTTON", L"Cancel", BS_OWNERDRAW | WS_TABSTOP, {-232, -48, -128, -16}},
      {IDOK, L"BUTTON", L"Save", BS_OWNERDRAW | WS_TABSTOP, {-120, -48, -24, -16}},
  }};
}

RECT Place(HWND dialog, const RECT& dip) {
  RECT client{};
  GetClientRect(dialog, &client);
  const auto x = [&](LONG value) { return value < 0 ? client.right + ui::Dip(dialog, value) : ui::Dip(dialog, value); };
  const auto y = [&](LONG value) { return value < 0 ? client.bottom + ui::Dip(dialog, value) : ui::Dip(dialog, value); };
  return {x(dip.left), y(dip.top), x(dip.right), y(dip.bottom)};
}

void ApplyFonts(HWND dialog, SettingsDialogState* state) {
  const std::wstring port = std::to_wstring(state->values.port);
  const auto controls = Controls(state->values, port);
  for (HFONT* font : {&state->font, &state->section_font, &state->hint_font}) {
    if (*font != nullptr) DeleteObject(*font);
  }
  state->font = ui::MakeFont(dialog, 13, FW_NORMAL);
  state->section_font = ui::MakeFont(dialog, 14, FW_SEMIBOLD);
  state->hint_font = ui::MakeFont(dialog, 12, FW_NORMAL);
  if (state->surface_brush != nullptr) DeleteObject(state->surface_brush);
  state->surface_brush = CreateSolidBrush(ui::Colors().surface);
  for (std::size_t index = 0; index < kControlCount; ++index) {
    const int id = controls[index].id;
    const HFONT font = id == kSectionId ? state->section_font : id == kHintId ? state->hint_font : state->font;
    SendMessageW(state->controls[index], WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
    ui::ApplyControlAppearance(state->controls[index]);
  }
}

void LayoutControls(HWND dialog, const SettingsDialogState& state) {
  const std::wstring port = std::to_wstring(state.values.port);
  const auto controls = Controls(state.values, port);
  for (std::size_t index = 0; index < kControlCount; ++index) {
    RECT bounds = Place(dialog, controls[index].dip);
    if (controls[index].id == IDC_SETTINGS_STARTUP_URL) {
      InflateRect(&bounds, -ui::Dip(dialog, 10), -ui::Dip(dialog, 7));
    }
    SetWindowPos(state.controls[index], nullptr, bounds.left, bounds.top, bounds.right - bounds.left,
                 bounds.bottom - bounds.top, SWP_NOZORDER | SWP_NOACTIVATE);
  }
}

void Paint(HWND dialog, HDC dc) {
  RECT client{};
  GetClientRect(dialog, &client);
  const auto colors = ui::Colors();
  const int footer = client.bottom - ui::Dip(dialog, kFooterDip);
  ui::FillSolid(dc, {0, 0, client.right, footer}, colors.surface);
  ui::FillSolid(dc, {0, footer, client.right, footer + 1}, colors.border);
  ui::FillSolid(dc, {0, footer + 1, client.right, client.bottom}, colors.canvas);
  HWND url = GetDlgItem(dialog, IDC_SETTINGS_STARTUP_URL);
  const RECT field = Place(dialog, kUrlFieldDip);
  ui::PaintRounded(dc, field, colors.surface, GetFocus() == url ? colors.focus : colors.border,
                   ui::Dip(dialog, 6), GetFocus() == url ? 2 : 1);
  const int divider = ui::Dip(dialog, 180);
  ui::FillSolid(dc, {ui::Dip(dialog, 24), divider, client.right - ui::Dip(dialog, 24), divider + 1}, colors.border);
}

void DrawButton(HWND dialog, const SettingsDialogState& state, const DRAWITEMSTRUCT& item) {
  const auto colors = ui::Colors();
  const bool primary = item.CtlID == IDOK;
  const bool pressed = (item.itemState & ODS_SELECTED) != 0;
  const bool focused = (item.itemState & ODS_FOCUS) != 0;
  const bool hovered = item.hwndItem == state.hovered;
  ui::FillSolid(item.hDC, item.rcItem, colors.canvas);
  COLORREF fill = primary ? colors.accent : colors.surface;
  if (pressed) fill = primary ? ui::Blend(RGB(0, 0, 0), colors.accent, 0.18) : colors.surface_hover;
  else if (hovered) fill = primary ? ui::Blend(RGB(255, 255, 255), colors.accent, 0.12) : colors.surface_hover;
  ui::PaintRounded(item.hDC, item.rcItem, fill, focused ? colors.focus : (primary ? fill : colors.border),
                   ui::Dip(dialog, 6), focused ? 2 : 1);
  wchar_t label[64]{};
  GetWindowTextW(item.hwndItem, label, static_cast<int>(std::size(label)));
  const COLORREF ink = primary && !ui::HighContrast() ? RGB(255, 255, 255) : colors.text;
  ui::DrawLabel(item.hDC, dialog, item.rcItem, label, ink, 13, primary ? FW_SEMIBOLD : FW_NORMAL, DT_CENTER);
}

// A themed checkbox ignores WM_CTLCOLORSTATIC's text colour, which leaves black
// text on the dark palette, so it draws its box from the theme and its label
// in the palette's ink while staying a real, accessible checkbox.
LRESULT DrawCheckbox(HWND dialog, NMCUSTOMDRAW* draw) {
  if (draw->dwDrawStage != CDDS_PREPAINT) return CDRF_DODEFAULT;
  const auto colors = ui::Colors();
  HWND button = draw->hdr.hwndFrom;
  const bool checked = SendMessageW(button, BM_GETCHECK, 0, 0) == BST_CHECKED;
  const bool hot = (draw->uItemState & CDIS_HOT) != 0;
  const bool pressed = (draw->uItemState & CDIS_SELECTED) != 0;
  ui::FillSolid(draw->hdc, draw->rc, colors.surface);
  const int box = ui::Dip(dialog, 18);
  RECT glyph{draw->rc.left + ui::Dip(dialog, 4), (draw->rc.top + draw->rc.bottom - box) / 2, 0, 0};
  glyph.right = glyph.left + box;
  glyph.bottom = glyph.top + box;
  HTHEME theme = OpenThemeData(button, L"BUTTON");
  if (theme != nullptr) {
    const int state = checked ? (pressed ? CBS_CHECKEDPRESSED : hot ? CBS_CHECKEDHOT : CBS_CHECKEDNORMAL)
                              : (pressed ? CBS_UNCHECKEDPRESSED : hot ? CBS_UNCHECKEDHOT : CBS_UNCHECKEDNORMAL);
    DrawThemeBackground(theme, draw->hdc, BP_CHECKBOX, state, &glyph, nullptr);
    CloseThemeData(theme);
  } else {
    DrawFrameControl(draw->hdc, &glyph, DFC_BUTTON, DFCS_BUTTONCHECK | (checked ? DFCS_CHECKED : 0));
  }
  RECT text = draw->rc;
  text.left = glyph.right + ui::Dip(dialog, 10);
  wchar_t label[64]{};
  GetWindowTextW(button, label, static_cast<int>(std::size(label)));
  ui::DrawLabel(draw->hdc, dialog, text, label, colors.text, 13);
  if ((draw->uItemState & CDIS_FOCUS) != 0) {
    RECT focus = text;
    const HGDIOBJ previous = SelectObject(draw->hdc, ui::CachedFont(dialog, 13));
    DrawTextW(draw->hdc, label, -1, &focus, DT_CALCRECT | DT_SINGLELINE | DT_NOPREFIX);
    SelectObject(draw->hdc, previous);
    const int height = focus.bottom - focus.top;
    focus.top = (text.top + text.bottom - height) / 2 - 1;
    focus.bottom = focus.top + height + 2;
    InflateRect(&focus, ui::Dip(dialog, 2), 0);
    DrawFocusRect(draw->hdc, &focus);
  }
  return CDRF_SKIPDEFAULT;
}

LRESULT CALLBACK HoverProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam, UINT_PTR id, DWORD_PTR data) {
  auto* state = reinterpret_cast<SettingsDialogState*>(data);
  if (message == WM_MOUSEMOVE && state->hovered != hwnd) {
    if (state->hovered != nullptr) InvalidateRect(state->hovered, nullptr, FALSE);
    state->hovered = hwnd;
    InvalidateRect(hwnd, nullptr, FALSE);
    TRACKMOUSEEVENT tracking{sizeof(tracking), TME_LEAVE, hwnd, 0};
    TrackMouseEvent(&tracking);
  } else if (message == WM_MOUSELEAVE && state->hovered == hwnd) {
    state->hovered = nullptr;
    InvalidateRect(hwnd, nullptr, FALSE);
  } else if (message == WM_NCDESTROY) {
    RemoveWindowSubclass(hwnd, &HoverProc, id);
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

void Finish(HWND dialog, SettingsDialogState* state, bool accept) {
  if (accept) {
    // Port and profile are launch-time capabilities. Keeping them read-only
    // avoids persisting settings the launcher cannot consume.
    state->values.startup_url = WindowText(GetDlgItem(dialog, IDC_SETTINGS_STARTUP_URL));
    state->values.isolate_new_tabs =
        SendMessageW(GetDlgItem(dialog, IDC_SETTINGS_ISOLATE_TABS), BM_GETCHECK, 0, 0) == BST_CHECKED;
    state->output_ref = state->values;
    state->accepted = true;
  }
  state->done = true;
  DestroyWindow(dialog);
}

LRESULT CALLBACK SettingsProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* state = reinterpret_cast<SettingsDialogState*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    state = reinterpret_cast<SettingsDialogState*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
  }
  if (state == nullptr) return DefWindowProcW(hwnd, message, wparam, lparam);

  switch (message) {
    case WM_CREATE: {
      ui::ApplyWindowAppearance(hwnd);
      const std::wstring port = std::to_wstring(state->values.port);
      const auto controls = Controls(state->values, port);
      for (std::size_t index = 0; index < kControlCount; ++index) {
        const auto& control = controls[index];
        HWND child = CreateWindowExW(0, control.kind, control.text, WS_CHILD | WS_VISIBLE | control.style, 0, 0,
                                     0, 0, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(control.id)),
                                     nullptr, nullptr);
        state->controls[index] = child;
        if ((control.style & BS_OWNERDRAW) != 0 && std::wstring_view(control.kind) == L"BUTTON") {
          SetWindowSubclass(child, &HoverProc, static_cast<UINT_PTR>(control.id),
                            reinterpret_cast<DWORD_PTR>(state));
        }
      }
      SendMessageW(GetDlgItem(hwnd, IDC_SETTINGS_ISOLATE_TABS), BM_SETCHECK,
                   state->values.isolate_new_tabs ? BST_CHECKED : BST_UNCHECKED, 0);
      ApplyFonts(hwnd, state);
      LayoutControls(hwnd, *state);
      return 0;
    }
    case ui::kDpiChangedMessage:
      ui::ApplySuggestedDpiRect(hwnd, lparam);
      ApplyFonts(hwnd, state);
      LayoutControls(hwnd, *state);
      InvalidateRect(hwnd, nullptr, TRUE);
      return 0;
    case WM_ERASEBKGND:
      return TRUE;
    case WM_PAINT: {
      PAINTSTRUCT paint{};
      HDC dc = BeginPaint(hwnd, &paint);
      Paint(hwnd, dc);
      EndPaint(hwnd, &paint);
      return 0;
    }
    case WM_CTLCOLORSTATIC:
    case WM_CTLCOLOREDIT: {
      const auto colors = ui::Colors();
      const int id = GetDlgCtrlID(reinterpret_cast<HWND>(lparam));
      SetTextColor(reinterpret_cast<HDC>(wparam), id == kHintId ? colors.muted_text : colors.text);
      SetBkColor(reinterpret_cast<HDC>(wparam), colors.surface);
      return reinterpret_cast<LRESULT>(state->surface_brush);
    }
    case WM_DRAWITEM:
      DrawButton(hwnd, *state, *reinterpret_cast<DRAWITEMSTRUCT*>(lparam));
      return TRUE;
    case WM_NOTIFY: {
      auto* notice = reinterpret_cast<NMHDR*>(lparam);
      if (notice != nullptr && notice->idFrom == IDC_SETTINGS_ISOLATE_TABS && notice->code == NM_CUSTOMDRAW) {
        return DrawCheckbox(hwnd, reinterpret_cast<NMCUSTOMDRAW*>(lparam));
      }
      break;
    }
    case WM_COMMAND:
      switch (LOWORD(wparam)) {
        case kTrustedComputersId:
          ShowTrustedComputers(hwnd);
          return 0;
        case kLocalAiId:
          if (state->show_ai) state->show_ai(hwnd);
          return 0;
        case IDC_SETTINGS_STARTUP_URL:
          if (HIWORD(wparam) == EN_SETFOCUS || HIWORD(wparam) == EN_KILLFOCUS) InvalidateRect(hwnd, nullptr, FALSE);
          return 0;
        case IDOK:
          Finish(hwnd, state, true);
          return 0;
        case IDCANCEL:
          Finish(hwnd, state, false);
          return 0;
        default:
          break;
      }
      break;
    case WM_CLOSE:
      Finish(hwnd, state, false);
      return 0;
    case WM_DESTROY:
      for (HFONT font : {state->font, state->section_font, state->hint_font}) {
        if (font != nullptr) DeleteObject(font);
      }
      if (state->surface_brush != nullptr) DeleteObject(state->surface_brush);
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
                             SettingsValues& updated_values,
                             std::function<void(HWND)> show_ai) {
  const wchar_t kClassName[] = L"KelpieSettingsDialog";
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = &SettingsProc;
  window_class.hInstance = instance;
  window_class.lpszClassName = kClassName;
  window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  RegisterClassW(&window_class);

  SettingsDialogState state(initial_values, updated_values);
  state.show_ai = std::move(show_ai);
  // Created at its final place: centred over the browser, at its DPI.
  const RECT frame = ui::OwnedWindowRect(owner, kClientDip, kStyle, kExStyle);
  HWND dialog = CreateWindowExW(kExStyle, kClassName, L"Settings", kStyle, frame.left, frame.top,
                                frame.right - frame.left, frame.bottom - frame.top, owner, nullptr,
                                instance, &state);
  if (dialog == nullptr) {
    return false;
  }

  EnableWindow(owner, FALSE);
  ShowWindow(dialog, SW_SHOW);
  SetForegroundWindow(dialog);
  HWND url = GetDlgItem(dialog, IDC_SETTINGS_STARTUP_URL);
  SetFocus(url);
  SendMessageW(url, EM_SETSEL, 0, -1);

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
