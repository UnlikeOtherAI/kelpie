#include "downloads_popup.h"

#include <commctrl.h>
#include <shellapi.h>
#include <shlobj.h>
#include <algorithm>
#include <array>
#include <limits>
#include "theme/theme.h"
#include "windows_utf.h"

namespace kelpie::windows {
namespace {
constexpr wchar_t kClass[] = L"KelpieDownloadsPopup";
constexpr int kClear = 2;
constexpr int kFirstRow = 100;
constexpr int kPage = 5;

struct Popup {
  DownloadHistory& history;
  int first = 0;
  std::array<uint64_t, kPage> row_ids{};
  uint64_t revision = std::numeric_limits<uint64_t>::max();
};

HWND Child(HWND window, const wchar_t* type, const wchar_t* text, DWORD style, int id,
           int x, int y, int width, int height) {
  auto child = CreateWindowExW(0, type, text, WS_CHILD | WS_VISIBLE | style, ui::Dip(window, x), ui::Dip(window, y),
                               ui::Dip(window, width), ui::Dip(window, height), window,
                               reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), GetModuleHandleW(nullptr), nullptr);
  SendMessageW(child, WM_SETFONT, reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
  return child;
}

void Refresh(HWND window, Popup& popup, bool force = false) {
  if (!force && popup.revision == popup.history.revision()) return;
  popup.revision = popup.history.revision();
  const auto& items = popup.history.items();
  int count = static_cast<int>(items.size());
  popup.first = std::clamp(popup.first, 0, std::max(0, count - kPage));
  SCROLLINFO scroll{sizeof(scroll), SIF_RANGE | SIF_PAGE | SIF_POS};
  scroll.nMax = std::max(0, count - 1);
  scroll.nPage = kPage;
  scroll.nPos = popup.first;
  SetScrollInfo(window, SB_VERT, &scroll, TRUE);
  for (int offset = 0; offset < kPage; ++offset) {
    int id = kFirstRow + 2 * offset;
    for (auto child_id : {id, id + 1}) if (auto child = GetDlgItem(window, child_id)) DestroyWindow(child);
    if (popup.first + offset >= count) continue;
    const auto& item = items[popup.first + offset];
    popup.row_ids[offset] = item.id;
    int y = 42 + 32 * offset;
    const auto text = utf::Utf8ToWideDisplay(item.name + "  -  " + DownloadHistory::Label(item.state));
    if (item.state == DownloadHistory::State::complete) {
      Child(window, L"BUTTON", text.c_str(), BS_OWNERDRAW | WS_TABSTOP, id, 8, y, 247, 30);
      Child(window, L"BUTTON", L"Show in File Explorer", BS_OWNERDRAW | WS_TABSTOP, id + 1, 256, y, 32, 30);
    } else {
      Child(window, L"STATIC", text.c_str(), SS_CENTERIMAGE | SS_ENDELLIPSIS, id, 10, y, 280, 30);
    }
  }
  if (!count) Child(window, L"STATIC", L"No downloads", 0, kFirstRow, 10, 44, 260, 24);
  EnableWindow(GetDlgItem(window, kClear), std::any_of(items.begin(), items.end(), [](const auto& item) {
    return item.state != DownloadHistory::State::downloading;
  }));
}

void DrawRow(const DRAWITEMSTRUCT& draw) {
  RECT rect = draw.rcItem;
  FillRect(draw.hDC, &rect, GetSysColorBrush(COLOR_WINDOW));
  if ((draw.CtlID - kFirstRow) % 2 == 0) {
    wchar_t text[512]{};
    GetWindowTextW(draw.hwndItem, text, 512);
    SetBkMode(draw.hDC, TRANSPARENT);
    SetTextColor(draw.hDC, GetSysColor(COLOR_WINDOWTEXT));
    rect.left += ui::Dip(draw.hwndItem, 2);
    DrawTextW(draw.hDC, text, -1, &rect, DT_LEFT | DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX);
  } else {
    const int radius = ui::Dip(draw.hwndItem, 5);
    const int x = (rect.left + rect.right) / 2 - radius / 2, y = (rect.top + rect.bottom) / 2 - radius / 2;
    auto pen = CreatePen(PS_SOLID, ui::Dip(draw.hwndItem, 2), GetSysColor(COLOR_WINDOWTEXT));
    auto old_pen = SelectObject(draw.hDC, pen);
    auto old_brush = SelectObject(draw.hDC, GetStockObject(NULL_BRUSH));
    Ellipse(draw.hDC, x - radius, y - radius, x + radius, y + radius);
    MoveToEx(draw.hDC, x + radius - 1, y + radius - 1, nullptr);
    LineTo(draw.hDC, x + 2 * radius, y + 2 * radius);
    SelectObject(draw.hDC, old_brush);
    SelectObject(draw.hDC, old_pen);
    DeleteObject(pen);
  }
  if (draw.itemState & ODS_FOCUS) DrawFocusRect(draw.hDC, &draw.rcItem);
}

void Activate(HWND window, Popup& popup, int id) {
  const auto offset = (id - kFirstRow) / 2;
  if (offset < 0 || offset >= kPage) return;
  const auto& items = popup.history.items();
  const auto item = std::find_if(items.begin(), items.end(), [&](const auto& row) { return row.id == popup.row_ids[offset]; });
  if (item == items.end() || item->state != DownloadHistory::State::complete) return;
  const auto path = item->path;
  if ((id - kFirstRow) % 2 == 0) {
    ShellExecuteW(window, L"open", path.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
  } else if (auto selection = ILCreateFromPathW(path.c_str())) {
    SHOpenFolderAndSelectItems(selection, 0, nullptr, 0);
    CoTaskMemFree(selection);
  }
}

LRESULT CALLBACK DownloadsProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  auto* popup = reinterpret_cast<Popup*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  switch (msg) {
    case WM_CREATE: {
      auto* history = static_cast<DownloadHistory*>(reinterpret_cast<CREATESTRUCTW*>(lp)->lpCreateParams);
      popup = new Popup{*history};
      SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(popup));
      Child(hwnd, L"STATIC", L"Downloads", 0, 0, 10, 12, 180, 24);
      Child(hwnd, L"BUTTON", L"Clear", WS_TABSTOP, kClear, 225, 6, 64, 26);
      Refresh(hwnd, *popup);
      SetTimer(hwnd, 1, 250, nullptr);
      return 0;
    }
    case WM_DRAWITEM: DrawRow(*reinterpret_cast<DRAWITEMSTRUCT*>(lp)); return TRUE;
    case WM_TIMER:
      if (popup) Refresh(hwnd, *popup);
      return 0;
    case WM_COMMAND:
      if (!popup || HIWORD(wp) != BN_CLICKED) break;
      if (LOWORD(wp) == kClear) { popup->history.ClearFinished(); Refresh(hwnd, *popup); }
      if (LOWORD(wp) >= kFirstRow) Activate(hwnd, *popup, LOWORD(wp));
      return 0;
    case WM_MOUSEWHEEL:
    case WM_VSCROLL:
      if (!popup) break;
      if (msg == WM_MOUSEWHEEL) popup->first -= GET_WHEEL_DELTA_WPARAM(wp) / WHEEL_DELTA;
      else switch (LOWORD(wp)) {
        case SB_LINEUP: --popup->first; break;
        case SB_LINEDOWN: ++popup->first; break;
        case SB_PAGEUP: popup->first -= kPage; break;
        case SB_PAGEDOWN: popup->first += kPage; break;
        case SB_THUMBTRACK: popup->first = HIWORD(wp); break;
        default: return 0;
      }
      Refresh(hwnd, *popup, true);
      return 0;
    case WM_ACTIVATE:
      if (LOWORD(wp) == WA_INACTIVE) PostMessageW(hwnd, WM_CLOSE, 0, 0);
      break;
    case WM_KEYDOWN:
      if (wp == VK_ESCAPE) { DestroyWindow(hwnd); return 0; }
      break;
    case WM_NCDESTROY:
      SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
      delete popup;
      break;
  }
  return DefWindowProcW(hwnd, msg, wp, lp);
}
}  // namespace

void ShowDownloadsPopup(HWND parent, HWND anchor, DownloadHistory& history) {
  WNDCLASSW cls{};
  cls.lpfnWndProc = DownloadsProc;
  cls.hInstance = GetModuleHandleW(nullptr);
  cls.lpszClassName = kClass;
  cls.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  cls.hbrBackground = GetSysColorBrush(COLOR_WINDOW);
  RegisterClassW(&cls);
  RECT at{};
  GetWindowRect(anchor, &at);
  const int width = ui::Dip(parent, 318), height = ui::Dip(parent, 206);
  auto window = CreateWindowExW(WS_EX_TOOLWINDOW, kClass, L"Downloads", WS_POPUP | WS_BORDER | WS_VSCROLL,
                                at.right - width, at.bottom, width, height, parent, nullptr, cls.hInstance, &history);
  if (window) { ShowWindow(window, SW_SHOW); SetForegroundWindow(window); }
}
}  // namespace kelpie::windows
