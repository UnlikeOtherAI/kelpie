#include <windows.h>

#pragma comment(linker, "/manifestdependency:\"type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'\"")

#include <commctrl.h>
#include <objidl.h>

#include <gdiplus.h>

#include <cstddef>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <optional>
#include <string>
#include <vector>

#include "resource.h"
#include "theme/theme.h"
#include "win32_shell.h"

namespace {

class PreviewDelegate final : public kelpie::windows::ShellDelegate {
 public:
  std::string GetBookmarksJson() const override { return "[]"; }
  std::string GetHistoryJson() const override { return "[]"; }
  std::string GetNetworkJson() const override { return "[]"; }
  std::string GetTabsJson() const override {
    std::string json = R"({"tabs":[)";
    for (int index = 0; index < tab_count; ++index) {
      if (index != 0) json += ',';
      json += "{\"id\":\"tab-" + std::to_string(index) + "\",\"generation\":" +
          std::to_string(index + 1) + ",\"title\":\"" +
          (index == 1 && background_title_changed ? "Updated API reference" : "Workspace tab") +
          "\",\"url\":\"https://kelpie.dev/" + std::to_string(index) +
          "\",\"active\":" + (index == 0 ? "true" : "false") + '}';
    }
    return json + "]}";
  }
  kelpie::windows::SettingsValues CurrentSettings() const override { return {}; }
  void OnCreateTabRequested() override {}
  void OnCreateIsolatedTabRequested() override {}
  void OnActivateTabRequested(std::string, std::uint64_t) override {}
  void OnCloseTabRequested(std::string, std::uint64_t) override {}
  void OnWindowCloseRequested() override {}
  void OnNavigateRequested(const std::string&) override {}
  void OnBackRequested() override {}
  void OnForwardRequested() override {}
  void OnReloadRequested() override {}
  void OnOpenSettingsRequested() override {}
  std::optional<std::wstring> BestUrlCompletion(std::wstring_view) const override { return std::nullopt; }
  int tab_count = 2;
  bool background_title_changed = false;
};

class PreviewObserver final : public kelpie::windows::BrowserStateObserver {
 public:
  void OnBrowserStateChanged(const kelpie::windows::BrowserState&) override {}
};

bool Expect(bool value, const char* message) {
  if (value) return true;
  std::cerr << message << std::endl;
  return false;
}

bool SavePng(HBITMAP bitmap, const std::filesystem::path& path) {
  Gdiplus::Bitmap image(bitmap, nullptr);
  UINT encoders = 0;
  UINT bytes = 0;
  if (Gdiplus::GetImageEncodersSize(&encoders, &bytes) != Gdiplus::Ok || bytes == 0) return false;
  std::vector<std::byte> storage(bytes);
  auto* codecs = reinterpret_cast<Gdiplus::ImageCodecInfo*>(storage.data());
  if (Gdiplus::GetImageEncoders(encoders, bytes, codecs) != Gdiplus::Ok) return false;
  for (UINT index = 0; index < encoders; ++index) {
    if (wcscmp(codecs[index].MimeType, L"image/png") == 0) {
      return image.Save(path.c_str(), &codecs[index].Clsid, nullptr) == Gdiplus::Ok;
    }
  }
  return false;
}

}  // namespace

int main() {
  INITCOMMONCONTROLSEX controls{sizeof(controls), ICC_LISTVIEW_CLASSES | ICC_TAB_CLASSES | ICC_BAR_CLASSES};
  if (!Expect(InitCommonControlsEx(&controls) != FALSE, "common controls failed")) return 1;
  Gdiplus::GdiplusStartupInput startup_input;
  ULONG_PTR token = 0;
  if (!Expect(Gdiplus::GdiplusStartup(&token, &startup_input, nullptr) == Gdiplus::Ok, "GDI+ failed")) return 1;

  PreviewDelegate delegate;
  PreviewObserver observer;
  kelpie::windows::Win32BrowserView browser;
  kelpie::windows::Win32Shell shell(GetModuleHandleW(nullptr), &delegate, &observer, &browser);
  if (!Expect(shell.Create(L"Kelpie — Visual Preview", 1120, 760), "shell failed to create")) return 1;
  const kelpie::windows::BrowserState state{"https://kelpie.dev", "Kelpie workspace", false, true, true};
  shell.UpdateBrowserState(state);
  bool passed = true;
  MSG tab{shell.hwnd(), WM_KEYDOWN, VK_TAB, 0, 0, {0, 0}};
  passed &= Expect(!shell.HandleKeyboardNavigation(tab),
                   "bare Tab without a chrome focus owner was consumed");
  ValidateRect(shell.hwnd(), nullptr);
  shell.UpdateBrowserState(state);
  RECT invalid{};
  passed &= Expect(GetUpdateRect(shell.hwnd(), &invalid, FALSE) == FALSE,
                   "unchanged browser state invalidated the shell");
  delegate.background_title_changed = true;
  shell.UpdateBrowserState(state);
  delegate.tab_count = 20;
  shell.UpdateBrowserState(state);
  bool found_hidden_close = false;
  for (int index = 0; index < delegate.tab_count; ++index) {
    HWND close = GetDlgItem(shell.hwnd(), 2000 + index);
    if (close == nullptr) continue;
    if ((GetWindowLongPtrW(close, GWL_STYLE) & WS_VISIBLE) == 0) found_hidden_close = true;
  }
  passed &= Expect(found_hidden_close, "overflow close controls were not hidden");
  HWND strip = GetDlgItem(shell.hwnd(), IDC_TAB_STRIP);
  HWND scroll = FindWindowExW(strip, nullptr, UPDOWN_CLASSW, nullptr);
  HWND first_close = GetDlgItem(shell.hwnd(), 2000);
  RECT before{};
  GetWindowRect(first_close, &before);
  if (scroll != nullptr) {
    SendMessageW(strip, TCM_SETCURFOCUS, delegate.tab_count - 1, 0);
    RECT after{};
    GetWindowRect(first_close, &after);
    const bool moved = before.left != after.left || before.right != after.right ||
        ((GetWindowLongPtrW(first_close, GWL_STYLE) & WS_VISIBLE) == 0);
    passed &= Expect(moved, "tab scroll did not relayout close controls");
  }

  // Pills share the strip like the macOS tab bar: wide when few, narrower when
  // many, and never outside the clamp in either direction.
  const auto pill_width = [&](int count) {
    delegate.tab_count = count;
    shell.UpdateBrowserState(state);
    RECT item{};
    if (!TabCtrl_GetItemRect(GetDlgItem(shell.hwnd(), IDC_TAB_STRIP), 0, &item)) return 0L;
    return item.right - item.left;
  };
  const LONG few = pill_width(2);
  const LONG many = pill_width(20);
  const UINT dpi = kelpie::windows::ui::WindowDpi(shell.hwnd());
  const LONG minimum = MulDiv(kelpie::windows::kTabMinWidthDip, static_cast<int>(dpi), 96);
  const LONG maximum = MulDiv(kelpie::windows::kTabMaxWidthDip, static_cast<int>(dpi), 96);
  passed &= Expect(few > many, "tab pills did not widen when fewer tabs were open");
  passed &= Expect(few <= maximum, "a sparse strip stretched a pill past the clamp");
  passed &= Expect(many >= minimum, "a crowded strip shrank a pill below the clamp");
  delegate.tab_count = 20;
  shell.UpdateBrowserState(state);

  constexpr int kWidth = 1120;
  constexpr int kHeight = 760;
  HDC screen = GetDC(nullptr);
  HDC memory = CreateCompatibleDC(screen);
  HBITMAP bitmap = CreateCompatibleBitmap(screen, kWidth, kHeight);
  ReleaseDC(nullptr, screen);
  HGDIOBJ old = SelectObject(memory, bitmap);
  RECT bounds{0, 0, kWidth, kHeight};
  FillRect(memory, &bounds, static_cast<HBRUSH>(GetStockObject(WHITE_BRUSH)));
  SendMessageW(shell.hwnd(), WM_PRINT, reinterpret_cast<WPARAM>(memory), PRF_CLIENT | PRF_CHILDREN | PRF_ERASEBKGND);

  const auto* output = std::getenv("KELPIE_SHELL_PREVIEW");
  passed &= Expect(GetPixel(memory, 8, 8) != RGB(255, 255, 255), "shell paint was empty");
  if (output != nullptr && *output != '\0') {
    const std::filesystem::path path(output);
    std::filesystem::create_directories(path.parent_path());
    passed &= Expect(SavePng(bitmap, path), "failed to write shell PNG");
  }

  SelectObject(memory, old);
  DeleteObject(bitmap);
  DeleteDC(memory);
  shell.Close();
  Gdiplus::GdiplusShutdown(token);
  return passed ? 0 : 1;
}
