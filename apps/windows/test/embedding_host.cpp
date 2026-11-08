#include "kelpie/browser.h"

#if defined(HAS_CEF)
#include <chrono>
#include <memory>
#include <thread>

namespace {
constexpr int kMove = 1001;
constexpr int kCloseBrowser = 1002;
constexpr UINT kSignIn = WM_APP + 1;
constexpr UINT kSignOut = WM_APP + 2;
struct Host {
  HWND main = nullptr, other = nullptr, first = nullptr, second = nullptr, status = nullptr;
  std::unique_ptr<kelpie::windows::BrowserSession> browser;
  bool closing = false;
};

void Layout(Host& host, HWND window) {
  RECT bounds{};
  GetClientRect(window, &bounds);
  const HWND pane = window == host.main ? host.first : host.second;
  if (pane) {
    MoveWindow(pane, 0, 70, bounds.right, bounds.bottom - 70, TRUE);
    if (host.browser && GetParent(host.browser->window()) == pane)
      MoveWindow(host.browser->window(), 0, 0, bounds.right, bounds.bottom - 70, TRUE);
  }
}

LRESULT CALLBACK HostProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* host = reinterpret_cast<Host*>(GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    host = static_cast<Host*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
    SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(host));
  }
  if (!host) return DefWindowProcW(window, message, wparam, lparam);
  switch (message) {
    case WM_SIZE: Layout(*host, window); return 0;
    case WM_COMMAND:
      if (LOWORD(wparam) == kMove && host->browser) {
        const HWND target = GetParent(host->browser->window()) == host->first ? host->second : host->first;
        host->browser->AttachTo(target);
        ShowWindow(target == host->second ? host->other : host->main, SW_SHOWNA);
        SetWindowTextW(host->status, target == host->second ? L"Browser moved to the second window." : L"Browser moved back.");
      } else if (LOWORD(wparam) == kCloseBrowser && host->browser) {
        host->browser->RequestClose();
      }
      return 0;
    case kSignIn:
      SetWindowTextW(host->status, L"Kelpie requested sign-in from the host's UOA session.");
      return 0;
    case kSignOut:
      SetWindowTextW(host->status, L"Kelpie requested sign-out from the host's UOA session.");
      return 0;
    case WM_CLOSE:
      if (window == host->other) {
        if (host->browser) host->browser->AttachTo(host->first);
        ShowWindow(window, SW_HIDE);
      } else if (host->browser) {
        host->closing = true;
        host->browser->RequestClose();
      } else {
        DestroyWindow(window);
      }
      return 0;
    case WM_DESTROY:
      if (window == host->main) PostQuitMessage(0);
      return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

int RunHost(HINSTANCE resources, HINSTANCE process, PWSTR, int show, void* sandbox) {
  Host host;
  WNDCLASSW type{};
  type.lpfnWndProc = HostProc;
  type.hInstance = resources;
  type.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  type.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  type.lpszClassName = L"KelpieEmbeddingHost";
  RegisterClassW(&type);
  host.main = CreateWindowExW(0, type.lpszClassName, L"Kelpie SDK host",
      WS_OVERLAPPEDWINDOW, 30, 40, 950, 750, nullptr, nullptr, resources, &host);
  host.other = CreateWindowExW(0, type.lpszClassName, L"Kelpie SDK second window",
      WS_OVERLAPPEDWINDOW, 500, 120, 950, 750, nullptr, nullptr, resources, &host);
  if (!host.main || !host.other) return 1;
  CreateWindowExW(0, L"BUTTON", L"Move browser", WS_CHILD | WS_VISIBLE | WS_TABSTOP,
      8, 8, 140, 26, host.main, reinterpret_cast<HMENU>(kMove), resources, nullptr);
  CreateWindowExW(0, L"BUTTON", L"Close browser", WS_CHILD | WS_VISIBLE | WS_TABSTOP,
      156, 8, 140, 26, host.main, reinterpret_cast<HMENU>(kCloseBrowser), resources, nullptr);
  host.status = CreateWindowExW(0, L"STATIC", L"Browser UI and tabs belong to Kelpie.",
      WS_CHILD | WS_VISIBLE, 8, 40, 850, 25, host.main, nullptr, resources, nullptr);
  host.first = CreateWindowExW(0, L"STATIC", L"", WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN,
      0, 70, 950, 680, host.main, nullptr, resources, nullptr);
  host.second = CreateWindowExW(0, L"STATIC", L"", WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN,
      0, 70, 950, 680, host.other, nullptr, resources, nullptr);
  Layout(host, host.main);
  Layout(host, host.other);
  ShowWindow(host.main, show);

  // Signed-out provider: the fixture delegates account actions without storing credentials.
  auto uoa = std::make_shared<kelpie::account::HostSession>();
  uoa->state = [] { return kelpie::account::HostSessionState{}; };
  uoa->request = [](const auto&, const auto&, const auto&, const auto&) -> kelpie::account::AccountResponse {
    throw kelpie::account::AccountFailure(401);
  };
  uoa->sign_in = [window = host.main] { PostMessageW(window, kSignIn, 0, 0); };
  uoa->sign_out = [window = host.main] { PostMessageW(window, kSignOut, 0, 0); };
  kelpie::windows::BrowserConfiguration config;
  config.hosted = true;
  config.parent_window = host.first;
  config.uoa_session = uoa;
  config.port = 18431;
  config.port_overridden = true;
  config.sandbox_info = sandbox;
  config.cef_process_instance = process;
  host.browser = std::make_unique<kelpie::windows::BrowserSession>(resources, std::move(config));
  if (!host.browser->Start(SW_SHOW)) return 2;

  MSG message{};
  bool running = true;
  while (running) {
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      if (message.message == WM_QUIT) { running = false; break; }
      if (!host.browser || !host.browser->ProcessMessage(message)) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
      }
    }
    if (host.browser) {
      host.browser->Tick();
      if (host.browser->IsClosed()) {
        host.browser.reset();
        SetWindowTextW(host.status, L"Browser closed. The host is still running.");
        if (host.closing) DestroyWindow(host.main);
      }
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  DestroyWindow(host.other);
  return 0;
}
}  // namespace

extern "C" __declspec(dllexport) int RunWinMain(HINSTANCE instance, LPWSTR command_line,
    int show_command, void* sandbox_info, cef_version_info_t* version_info) {
  return kelpie::windows::BootstrapBrowserHost(instance, command_line, show_command,
                                               sandbox_info, version_info, &RunHost);
}
#endif
