#include "win32_shell.h"

#include <commctrl.h>

#include <iostream>

#include "resource.h"

namespace {

LPARAM ScreenPoint(int x, int y) {
  return static_cast<LPARAM>((static_cast<unsigned int>(y) & 0xffffU) << 16U |
                             (static_cast<unsigned int>(x) & 0xffffU));
}

bool Expect(bool condition, const char* message) {
  if (condition) return true;
  std::cerr << message << std::endl;
  return false;
}

class StubDelegate final : public kelpie::windows::ShellDelegate {
 public:
  void OnNavigateRequested(const std::string&) override {}
  void OnBackRequested() override {}
  void OnForwardRequested() override {}
  void OnReloadRequested() override {}
  void OnOpenSettingsRequested() override {}
  std::optional<std::wstring> BestUrlCompletion(std::wstring_view) const override {
    return std::nullopt;
  }

  std::string GetBookmarksJson() const override { return "[]"; }
  std::string GetHistoryJson() const override { return "[]"; }
  std::string GetNetworkJson() const override { return "[]"; }
  std::string GetTabsJson() const override {
    return R"({"tabs":[{"id":"tab-1","generation":1,"title":"First","active":true},{"id":"tab-2","generation":2,"title":"Second","active":false}]})";
  }
  kelpie::windows::SettingsValues CurrentSettings() const override {
    return {8420, L"", L"https://example.com"};
  }
  void OnCreateTabRequested() override {}
  void OnActivateTabRequested(std::string id, std::uint64_t generation) override {
    activated_id = std::move(id);
    activated_generation = generation;
  }
  void OnCloseTabRequested(std::string, std::uint64_t) override {}
  void OnWindowCloseRequested() override { close_requested = true; }

  mutable std::string activated_id;
  mutable std::uint64_t activated_generation = 0;
  mutable bool close_requested = false;
};

class StubObserver final : public kelpie::windows::BrowserStateObserver {
 public:
  void OnBrowserStateChanged(const kelpie::windows::BrowserState&) override {}
};

}  // namespace

int main() {
  INITCOMMONCONTROLSEX controls{
      sizeof(controls), ICC_LISTVIEW_CLASSES | ICC_STANDARD_CLASSES | ICC_TAB_CLASSES};
  if (!Expect(InitCommonControlsEx(&controls) != FALSE,
              "common controls failed to initialize")) {
    return 1;
  }

  HINSTANCE instance = GetModuleHandleW(nullptr);
  StubDelegate delegate;
  StubObserver observer;
  kelpie::windows::Win32BrowserView browser_view;
  kelpie::windows::Win32Shell shell(instance, &delegate, &observer, &browser_view);
  if (!Expect(shell.Create(L"Kelpie", 800, 600), "shell failed to create")) {
    return 1;
  }

  bool passed = true;
  RECT window_rect{};
  GetWindowRect(shell.hwnd(), &window_rect);
  passed &= Expect(
      SendMessageW(shell.hwnd(), WM_NCHITTEST, 0,
                   ScreenPoint((window_rect.left + window_rect.right) / 2,
                               window_rect.top + 20)) == HTCAPTION,
      "title strip is not draggable through Win32Shell");

  kelpie::windows::BrowserState state;
  state.url = "https://first.test";
  state.title = "First";
  shell.UpdateBrowserState(state);
  passed &= Expect(TabCtrl_GetItemCount(GetDlgItem(shell.hwnd(), IDC_TAB_STRIP)) == 2,
                   "tab strip did not populate from shell state");

  SendMessageW(shell.hwnd(), WM_COMMAND, IDM_NEXT_TAB, 0);
  passed &= Expect(delegate.activated_id == "tab-2" &&
                       delegate.activated_generation == 2,
                   "next-tab command was not routed through Win32Shell");

  SendMessageW(shell.hwnd(), WM_COMMAND, IDC_WINDOW_MAXIMIZE, 0);
  passed &= Expect(IsZoomed(shell.hwnd()) != FALSE,
                   "maximize caption command was not routed through Win32Shell");

  shell.Close();
  return passed ? 0 : 1;
}
