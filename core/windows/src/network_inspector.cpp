#include "network_inspector.h"

#include <commctrl.h>

#include <algorithm>
#include <array>

#include "display_format.h"
#include "theme/theme.h"

namespace kelpie::windows {
namespace {

constexpr int kListId = 100;
constexpr int kFilterId = 101;
constexpr int kClearId = 102;
constexpr int kFirstTypeId = 110;
constexpr UINT_PTR kRefreshTimer = 1;

struct Column {
  const wchar_t* title;
  int width_dip;  // 0 = the Name column, which takes the remaining width
  int format;
};

constexpr std::array<Column, 7> kColumns{{
    {L"Name", 0, LVCFMT_LEFT},
    {L"Method", 70, LVCFMT_LEFT},
    {L"Status", 76, LVCFMT_LEFT},
    {L"Type", 90, LVCFMT_LEFT},
    {L"Initiator", 80, LVCFMT_LEFT},
    {L"Size", 76, LVCFMT_RIGHT},
    {L"Time", 76, LVCFMT_RIGHT},
}};

const std::wstring& Cell(const NetworkRow& row, int column) {
  switch (column) {
    case 0: return row.name;
    case 1: return row.method;
    case 2: return row.status;
    case 3: return row.type;
    case 4: return row.initiator;
    case 5: return row.size;
    default: return row.time;
  }
}

COLORREF ErrorColor() {
  if (ui::HighContrast()) return GetSysColor(COLOR_WINDOWTEXT);
  return ui::DarkMode() ? RGB(242, 139, 130) : RGB(217, 48, 37);
}

}  // namespace

PanelWindow::Spec NetworkInspector::Describe() const {
  return {L"KelpieNetworkInspector", L"Network", {960, 560}, {660, 280}};
}

int NetworkInspector::ToolbarHeight() const { return ui::Dip(hwnd_, 40); }
int NetworkInspector::StatusHeight() const { return ui::Dip(hwnd_, 26); }

void NetworkInspector::CreateControls() {
  const auto make_button = [&](int id, const wchar_t* text) {
    HWND button = CreateWindowExW(0, L"BUTTON", text, WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
                                  0, 0, 0, 0, hwnd_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)),
                                  instance_, nullptr);
    SetWindowSubclass(button, &NetworkInspector::ButtonProc, static_cast<UINT_PTR>(id),
                      reinterpret_cast<DWORD_PTR>(this));
    return button;
  };
  clear_button_ = make_button(kClearId, L"Clear");
  filter_ = CreateWindowExW(0, L"EDIT", L"", WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_AUTOHSCROLL, 0, 0, 0,
                            0, hwnd_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kFilterId)), instance_,
                            nullptr);
  SendMessageW(filter_, EM_SETCUEBANNER, TRUE, reinterpret_cast<LPARAM>(L"Filter by address or method"));
  for (std::size_t index = 0; index < kRequestTypes.size(); ++index) {
    type_buttons_.push_back(make_button(kFirstTypeId + static_cast<int>(index), kRequestTypes[index].label));
  }
  list_ = CreateWindowExW(0, WC_LISTVIEWW, L"",
                          WS_CHILD | WS_VISIBLE | WS_TABSTOP | LVS_REPORT | LVS_SINGLESEL |
                              LVS_SHOWSELALWAYS | LVS_OWNERDATA,
                          0, 0, 0, 0, hwnd_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kListId)),
                          instance_, nullptr);
  for (std::size_t index = 0; index < kColumns.size(); ++index) {
    LVCOLUMNW column{};
    column.mask = LVCF_TEXT | LVCF_WIDTH | LVCF_FMT;
    column.pszText = const_cast<wchar_t*>(kColumns[index].title);
    column.fmt = kColumns[index].format;
    column.cx = ui::Dip(hwnd_, kColumns[index].width_dip == 0 ? 280 : kColumns[index].width_dip);
    ListView_InsertColumn(list_, static_cast<int>(index), &column);
  }
  tooltip_ = CreateWindowExW(WS_EX_TOPMOST, TOOLTIPS_CLASSW, nullptr, WS_POPUP | TTS_ALWAYSTIP, 0, 0, 0, 0,
                             hwnd_, nullptr, instance_, nullptr);
  TOOLINFOW tool{sizeof(tool)};
  tool.uFlags = TTF_SUBCLASS | TTF_IDISHWND;
  tool.hwnd = hwnd_;
  tool.uId = reinterpret_cast<UINT_PTR>(clear_button_);
  tool.lpszText = const_cast<wchar_t*>(L"Clear the request log");
  SendMessageW(tooltip_, TTM_ADDTOOLW, 0, reinterpret_cast<LPARAM>(&tool));
  ApplyTheme();
}

void NetworkInspector::ApplyTheme() {
  ui::StyleList(list_, font_);
  for (std::size_t index = 0; index < kColumns.size(); ++index) {
    if (kColumns[index].width_dip != 0) {
      ListView_SetColumnWidth(list_, static_cast<int>(index), ui::Dip(hwnd_, kColumns[index].width_dip));
    }
  }
  SendMessageW(filter_, WM_SETFONT, reinterpret_cast<WPARAM>(font_), TRUE);
  ui::ApplyControlAppearance(filter_);
  if (field_brush_ != nullptr) DeleteObject(field_brush_);
  field_brush_ = CreateSolidBrush(ui::Colors().surface);
}

void NetworkInspector::Layout(const RECT& client) {
  if (list_ == nullptr) return;
  const int pad = ui::Dip(hwnd_, 8);
  const int toolbar = ToolbarHeight();
  const int control = ui::Dip(hwnd_, 28);
  const int top = (toolbar - control) / 2;
  int x = pad;
  SetWindowPos(clear_button_, nullptr, x, top, control, control, SWP_NOZORDER);
  x += control + pad;

  // Type buttons are sized to their labels; the filter takes what is left,
  // within a range that keeps it usable without crowding the buttons.
  HDC dc = GetDC(hwnd_);
  const HGDIOBJ previous = SelectObject(dc, ui::CachedFont(hwnd_, 12, FW_SEMIBOLD));
  std::vector<int> widths;
  int types_width = 0;
  for (const auto& type : kRequestTypes) {
    SIZE text{};
    GetTextExtentPoint32W(dc, type.label, static_cast<int>(wcslen(type.label)), &text);
    widths.push_back(text.cx + ui::Dip(hwnd_, 18));
    types_width += widths.back() + ui::Dip(hwnd_, 2);
  }
  SelectObject(dc, previous);
  ReleaseDC(hwnd_, dc);
  const int filter_width = std::clamp<int>(client.right - x - types_width - 3 * pad, ui::Dip(hwnd_, 140),
                                           ui::Dip(hwnd_, 300));
  filter_frame_ = {x, top, x + filter_width, top + control};
  const int glyph = ui::Dip(hwnd_, 26);
  const int edit_height = ui::Dip(hwnd_, 20);
  SetWindowPos(filter_, nullptr, x + glyph, top + (control - edit_height) / 2,
               filter_width - glyph - ui::Dip(hwnd_, 8), edit_height, SWP_NOZORDER);
  x += filter_width + pad;
  separator_x_ = x;
  x += pad;
  const int chip = ui::Dip(hwnd_, 24);
  for (std::size_t index = 0; index < type_buttons_.size(); ++index) {
    SetWindowPos(type_buttons_[index], nullptr, x, (toolbar - chip) / 2, widths[index], chip, SWP_NOZORDER);
    x += widths[index] + ui::Dip(hwnd_, 2);
  }

  const int list_top = toolbar + 1;
  const int list_height = std::max(0, static_cast<int>(client.bottom) - list_top - StatusHeight() - 1);
  SetWindowPos(list_, nullptr, 0, list_top, client.right, list_height, SWP_NOZORDER);
  int fixed = GetSystemMetrics(SM_CXVSCROLL);
  for (std::size_t index = 1; index < kColumns.size(); ++index) {
    fixed += ListView_GetColumnWidth(list_, static_cast<int>(index));
  }
  ListView_SetColumnWidth(list_, 0, std::max(ui::Dip(hwnd_, 180), static_cast<int>(client.right) - fixed));
  InvalidateRect(hwnd_, nullptr, TRUE);
}

void NetworkInspector::OnShown() {
  Refresh();
  SetTimer(hwnd_, kRefreshTimer, 1000, nullptr);
}

void NetworkInspector::Refresh() {
  if (hwnd_ == nullptr || !supplier_) return;
  std::string next = supplier_();
  if (next == json_) return;
  const std::string selected = SelectedId();
  json_ = std::move(next);
  rows_ = ParseNetworkRows(json_);
  ApplyFilter(selected);
}

std::string NetworkInspector::SelectedId() const {
  const int selected = list_ == nullptr ? -1 : ListView_GetNextItem(list_, -1, LVNI_SELECTED);
  if (selected < 0 || static_cast<std::size_t>(selected) >= visible_.size()) return {};
  return rows_[visible_[static_cast<std::size_t>(selected)]].id;
}

void NetworkInspector::ApplyFilter(const std::string& selected_id) {
  if (list_ == nullptr) return;
  // Keep the selected request selected, and keep following the newest
  // request when the person was already looking at the end of the list.
  const int count = ListView_GetItemCount(list_);
  const bool following = count == 0 ||
      ListView_GetTopIndex(list_) + ListView_GetCountPerPage(list_) >= count;

  const int length = GetWindowTextLengthW(filter_);
  std::wstring text(static_cast<std::size_t>(std::max(length, 0)) + 1, L'\0');
  text.resize(static_cast<std::size_t>(GetWindowTextW(filter_, text.data(), length + 1)));
  visible_ = FilterNetworkRows(rows_, type_, text);

  ListView_SetItemState(list_, -1, 0, LVIS_SELECTED | LVIS_FOCUSED);
  ListView_SetItemCountEx(list_, static_cast<int>(visible_.size()), LVSICF_NOSCROLL);
  for (std::size_t index = 0; index < visible_.size() && !selected_id.empty(); ++index) {
    if (rows_[visible_[index]].id != selected_id) continue;
    ListView_SetItemState(list_, static_cast<int>(index), LVIS_SELECTED | LVIS_FOCUSED,
                          LVIS_SELECTED | LVIS_FOCUSED);
    break;
  }
  if (following && !visible_.empty()) ListView_EnsureVisible(list_, static_cast<int>(visible_.size()) - 1, FALSE);
  InvalidateRect(list_, nullptr, FALSE);
  RECT client{};
  GetClientRect(hwnd_, &client);
  client.top = client.bottom - StatusHeight();
  InvalidateRect(hwnd_, &client, TRUE);
}

std::wstring NetworkInspector::Summary() const {
  std::int64_t shown = 0;
  std::int64_t total = 0;
  for (const auto& row : rows_) total += row.bytes;
  for (const auto index : visible_) shown += rows_[index].bytes;
  if (visible_.size() == rows_.size()) {
    return std::to_wstring(rows_.size()) + (rows_.size() == 1 ? L" request" : L" requests") + L"  |  " +
           format::Bytes(total) + L" transferred";
  }
  return std::to_wstring(visible_.size()) + L" / " + std::to_wstring(rows_.size()) + L" requests  |  " +
         format::Bytes(shown) + L" / " + format::Bytes(total) + L" transferred";
}

void NetworkInspector::Paint(HDC dc) const {
  RECT client{};
  GetClientRect(hwnd_, &client);
  const auto colors = ui::Colors();
  const int toolbar = ToolbarHeight();
  ui::FillSolid(dc, {0, 0, client.right, toolbar}, colors.canvas);
  ui::FillSolid(dc, {0, toolbar, client.right, toolbar + 1}, colors.border);
  ui::PaintRounded(dc, filter_frame_, colors.surface,
                   GetFocus() == filter_ ? colors.focus : colors.border, ui::Dip(hwnd_, 6));
  const RECT glyph{filter_frame_.left, filter_frame_.top, filter_frame_.left + ui::Dip(hwnd_, 26),
                   filter_frame_.bottom};
  ui::DrawGlyph(dc, hwnd_, glyph, ui::icon::kFilter, colors.muted_text, 12);
  const int inset = ui::Dip(hwnd_, 10);
  ui::FillSolid(dc, {separator_x_, inset, separator_x_ + 1, toolbar - inset}, colors.border);

  const int status_top = client.bottom - StatusHeight();
  ui::FillSolid(dc, {0, status_top - 1, client.right, status_top}, colors.border);
  ui::FillSolid(dc, {0, status_top, client.right, client.bottom}, colors.canvas);
  const RECT text{ui::Dip(hwnd_, 10), status_top, client.right - ui::Dip(hwnd_, 10), client.bottom};
  ui::DrawLabel(dc, hwnd_, text, Summary().c_str(), colors.muted_text, 12);
}

bool NetworkInspector::DrawButton(const DRAWITEMSTRUCT& item) const {
  const auto colors = ui::Colors();
  const bool hovered = item.hwndItem == hovered_;
  const bool pressed = (item.itemState & ODS_SELECTED) != 0;
  const bool focused = (item.itemState & ODS_FOCUS) != 0;
  ui::FillSolid(item.hDC, item.rcItem, colors.canvas);
  if (item.CtlID == kClearId) {
    if (hovered || pressed || focused) {
      ui::PaintRounded(item.hDC, item.rcItem, colors.surface_hover, focused ? colors.focus : colors.surface_hover,
                       ui::Dip(hwnd_, 6), focused ? 2 : 0);
    }
    ui::DrawGlyph(item.hDC, hwnd_, item.rcItem, ui::icon::kClear, colors.text, 15);
    return true;
  }
  const auto index = static_cast<std::size_t>(item.CtlID - kFirstTypeId);
  if (index >= kRequestTypes.size()) return false;
  const bool selected = kRequestTypes[index].type == type_;
  if (selected || hovered || pressed || focused) {
    const COLORREF fill = selected ? ui::Blend(colors.accent, colors.canvas, 0.16) : colors.surface_hover;
    ui::PaintRounded(item.hDC, item.rcItem, fill, focused ? colors.focus : fill, ui::Dip(hwnd_, 12),
                     focused ? 2 : 0);
  }
  ui::DrawLabel(item.hDC, hwnd_, item.rcItem, kRequestTypes[index].label,
                selected ? colors.accent : colors.text, 12, FW_SEMIBOLD, DT_CENTER);
  return true;
}

LRESULT NetworkInspector::CustomDrawList(NMLVCUSTOMDRAW* draw) const {
  switch (draw->nmcd.dwDrawStage) {
    case CDDS_PREPAINT:
      return CDRF_NOTIFYITEMDRAW;
    case CDDS_ITEMPREPAINT:
      return CDRF_NOTIFYSUBITEMDRAW;
    case CDDS_ITEMPREPAINT | CDDS_SUBITEM: {
      const auto colors = ui::Colors();
      const auto row = static_cast<std::size_t>(draw->nmcd.dwItemSpec);
      // DevTools stripes alternate rows and prints failed requests in red.
      draw->clrTextBk = row % 2 == 1 && !ui::HighContrast() ? ui::Blend(colors.text, colors.surface, 0.035)
                                                             : colors.surface;
      const bool failed = row < visible_.size() && rows_[visible_[row]].failed;
      draw->clrText = failed ? ErrorColor() : (draw->iSubItem == 0 ? colors.text : colors.muted_text);
      return CDRF_NEWFONT;
    }
    default:
      return CDRF_DODEFAULT;
  }
}

LRESULT CALLBACK NetworkInspector::ButtonProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam,
                                              UINT_PTR subclass_id, DWORD_PTR reference_data) {
  auto* self = reinterpret_cast<NetworkInspector*>(reference_data);
  if (message == WM_MOUSEMOVE && self->hovered_ != hwnd) {
    if (self->hovered_ != nullptr) InvalidateRect(self->hovered_, nullptr, FALSE);
    self->hovered_ = hwnd;
    InvalidateRect(hwnd, nullptr, FALSE);
    TRACKMOUSEEVENT tracking{sizeof(tracking), TME_LEAVE, hwnd, 0};
    TrackMouseEvent(&tracking);
  } else if (message == WM_MOUSELEAVE && self->hovered_ == hwnd) {
    self->hovered_ = nullptr;
    InvalidateRect(hwnd, nullptr, FALSE);
  } else if (message == WM_NCDESTROY) {
    RemoveWindowSubclass(hwnd, &NetworkInspector::ButtonProc, subclass_id);
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

bool NetworkInspector::HandlePanelMessage(UINT message, WPARAM wparam, LPARAM lparam, LRESULT* result) {
  *result = 0;
  switch (message) {
    case WM_PAINT: {
      PAINTSTRUCT paint{};
      HDC dc = BeginPaint(hwnd_, &paint);
      Paint(dc);
      EndPaint(hwnd_, &paint);
      return true;
    }
    case WM_TIMER:
      if (wparam != kRefreshTimer) return false;
      if (IsShowing()) Refresh();
      else KillTimer(hwnd_, kRefreshTimer);
      return true;
    case WM_DRAWITEM:
      *result = DrawButton(*reinterpret_cast<DRAWITEMSTRUCT*>(lparam)) ? TRUE : FALSE;
      return true;
    case WM_CTLCOLOREDIT: {
      const auto colors = ui::Colors();
      SetTextColor(reinterpret_cast<HDC>(wparam), colors.text);
      SetBkColor(reinterpret_cast<HDC>(wparam), colors.surface);
      *result = reinterpret_cast<LRESULT>(field_brush_);
      return true;
    }
    case WM_DESTROY:
      if (field_brush_ != nullptr) DeleteObject(field_brush_);
      field_brush_ = nullptr;
      return false;
    case WM_COMMAND: {
      const int id = LOWORD(wparam);
      if (id == kFilterId && (HIWORD(wparam) == EN_CHANGE)) ApplyFilter(SelectedId());
      if (id == kFilterId && (HIWORD(wparam) == EN_SETFOCUS || HIWORD(wparam) == EN_KILLFOCUS)) {
        InvalidateRect(hwnd_, &filter_frame_, TRUE);
      }
      if (id == kClearId && HIWORD(wparam) == BN_CLICKED && clear_) {
        clear_();
        Refresh();
      }
      if (id >= kFirstTypeId && id < kFirstTypeId + static_cast<int>(kRequestTypes.size()) &&
          HIWORD(wparam) == BN_CLICKED) {
        type_ = kRequestTypes[static_cast<std::size_t>(id - kFirstTypeId)].type;
        for (HWND button : type_buttons_) InvalidateRect(button, nullptr, FALSE);
        ApplyFilter(SelectedId());
      }
      // Enter in the filter arrives as IDOK; there is nothing to submit.
      return id != IDCANCEL;
    }
    case WM_NOTIFY: {
      const auto* notice = reinterpret_cast<NMHDR*>(lparam);
      if (notice == nullptr || notice->idFrom != kListId) return false;
      if (notice->code == NM_CUSTOMDRAW) {
        *result = CustomDrawList(reinterpret_cast<NMLVCUSTOMDRAW*>(lparam));
        return true;
      }
      if (notice->code == LVN_GETDISPINFOW) {
        auto* info = reinterpret_cast<NMLVDISPINFOW*>(lparam);
        const auto row = static_cast<std::size_t>(info->item.iItem);
        if ((info->item.mask & LVIF_TEXT) != 0 && row < visible_.size()) {
          wcsncpy_s(info->item.pszText, info->item.cchTextMax,
                    Cell(rows_[visible_[row]], info->item.iSubItem).c_str(), _TRUNCATE);
        }
        return true;
      }
      if (notice->code == LVN_GETINFOTIPW) {
        auto* tip = reinterpret_cast<NMLVGETINFOTIPW*>(lparam);
        const auto row = static_cast<std::size_t>(tip->iItem);
        if (row < visible_.size()) wcsncpy_s(tip->pszText, tip->cchTextMax, rows_[visible_[row]].url.c_str(), _TRUNCATE);
        return true;
      }
      if (notice->code == LVN_GETEMPTYMARKUP) {
        const wchar_t* message_text = rows_.empty()
            ? L"Recording network activity. Load or reload a page to see its requests."
            : L"No requests match this filter.";
        *result = ui::AnswerEmptyMarkup(lparam, message_text) ? TRUE : FALSE;
        return true;
      }
      return false;
    }
    default:
      return false;
  }
}

}  // namespace kelpie::windows
