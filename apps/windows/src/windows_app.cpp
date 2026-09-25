#include "windows_app.h"

#include "windows_utf.h"

#include <commctrl.h>

#include <algorithm>
#include <cctype>
#include <thread>

#include <atomic>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <rpc.h>


namespace kelpie::windows {
namespace {

constexpr UINT_PTR kCloseRetryTimerId = 0x4B51;

std::optional<TabLease> ActiveLease(DesktopApp* app) {
  if (app == nullptr) return std::nullopt;
  std::vector<TabSnapshot> tabs;
  if (!app->engine().GetTabs(&tabs, std::chrono::seconds(2)).ok) return std::nullopt;
  for (const auto& tab : tabs) {
    if (tab.active) return TabLease{tab.id, tab.generation};
  }
  return std::nullopt;
}

bool HasScheme(const std::string& value) {
  const auto colon = value.find(':');
  return colon != std::string::npos && colon > 0 &&
      std::all_of(value.begin(), value.begin() + static_cast<std::ptrdiff_t>(colon),
                  [](unsigned char c) { return std::isalnum(c) || c == '+' || c == '-' || c == '.'; });
}

// A fresh partition id for an isolated tab. A UUID rather than a counter: the
// id has to stay unique against partitions restored from a previous session,
// which the counter would know nothing about.
std::string NewIsolatedPartitionId() {
  UUID uuid{};
  if (UuidCreate(&uuid) != RPC_S_OK) return std::string();
  RPC_CSTR text = nullptr;
  if (UuidToStringA(&uuid, &text) != RPC_S_OK || text == nullptr) return std::string();
  std::string id = "isolated-" + std::string(reinterpret_cast<const char*>(text));
  RpcStringFreeA(&text);
  return id;
}

}  // namespace

WindowsApp::WindowsApp(HINSTANCE instance, AppConfig config)
    : instance_(instance),
      config_(std::move(config)),
      device_info_provider_(config_.profile_dir),
      browser_view_(std::make_unique<Win32BrowserView>()),
      settings_view_(std::make_unique<SettingsView>()) {
  shell_ = std::make_unique<Win32Shell>(instance_, this, this, browser_view_.get());
}

WindowsApp::~WindowsApp() {
  // Failed startup and exceptional exits use the same ownership barrier as a
  // normal WM_CLOSE. A DesktopApp with live CEF callbacks must remain owned
  // until its HTTP workers and browser close have drained.
  while (!ShutdownDesktopRuntime()) {
    if (desktop_app_ != nullptr) desktop_app_->Tick();
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
}

int WindowsApp::Run(int show_command) {
  ResolveProfileDirectory();
  std::string session_error;
  startup_diagnostics_.Enter(StartupStage::kProfileOwnership);
  if (!profile_session_.Open(config_.profile_dir, config_.readiness_path, &session_error)) {
    startup_diagnostics_.Fail(StartupStage::kProfileOwnership, session_error);
    return 1;
  }
  LoadSettings();
  LoadSession();
  if (!InitializeCommonControls()) return 1;
  if (!CreateShell(show_command)) return 1;
  const bool browser_ready = InitializeDesktopRuntime();
  // A hidden launch has nobody to read the diagnostic, so it fails promptly
  // instead of lingering as an invisible process its launcher must time out.
  // Ask the window rather than `show_command`: the CEF bootstrap may pass
  // SW_SHOWDEFAULT, which only resolves to the launcher's SW_HIDE in ShowWindow.
  if (!browser_ready && !IsWindowVisible(shell_->hwnd())) return 1;
  if (!browser_ready) {
    browser_view_->UpdateFallbackText(startup_diagnostics_.Presentation());
    browser_view_->ShowFallback(true);
  }

  MSG message{};
  while (running_ && GetMessageW(&message, nullptr, 0, 0) > 0) {
    const bool accelerator_handled =
        shell_ != nullptr && TranslateAcceleratorW(shell_->hwnd(), shell_->accelerators(), &message);
    if (!accelerator_handled) {
      // Bare Tab is chrome traversal only after standard accelerators such as
      // Ctrl+Tab have had first refusal.
      if (shell_ == nullptr || !shell_->HandleKeyboardNavigation(message)) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
      }
    }
    UpdateBrowserStateFromRuntime();
    // A forced CEF close can outlive the first WM_CLOSE dispatch. Pump-driven
    // callbacks re-enter this owner loop and complete the same close request.
    TryCompleteClose();
  }

  if (!close_lifecycle_.requested()) {
    close_lifecycle_.Request();
    if (desktop_app_ != nullptr) desktop_app_->BeginShutdown();
  }
  // WM_QUIT bypasses the shell timer. Keep the native owner available for HTTP
  // handlers admitted before the close gate and for bounded CEF close retries.
  while (!TryCompleteClose()) {
    if (desktop_app_ != nullptr) desktop_app_->Tick();
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  return browser_ready ? 0 : 1;
}

void WindowsApp::OnNavigateRequested(const std::string& url) {
  if (!desktop_app_) return;
  const auto first = url.find_first_not_of(" \t\r\n");
  const auto last = url.find_last_not_of(" \t\r\n");
  const std::string trimmed = first == std::string::npos ? std::string() : url.substr(first, last - first + 1);
  const std::string resolved = HasScheme(trimmed) ? trimmed : "https://" + trimmed;
  const auto lease = ActiveLease(desktop_app_.get());
  const auto result = lease ? desktop_app_->engine().Navigate(*lease, resolved, nullptr, std::chrono::seconds(5))
                            : BrowserControlResult::Failure("TAB_NOT_FOUND", "No active tab exists");
  if (!result.ok && shell_) shell_->ShowToast(utf::Utf8ToWideDisplay(result.message));
}

void WindowsApp::OnBackRequested() {
  const auto lease = ActiveLease(desktop_app_.get());
  if (!lease) return;
  const auto result = desktop_app_->engine().Back(*lease, nullptr, std::chrono::seconds(2));
  if (!result.ok && shell_) shell_->ShowToast(utf::Utf8ToWideDisplay(result.message));
}

void WindowsApp::OnForwardRequested() {
  const auto lease = ActiveLease(desktop_app_.get());
  if (!lease) return;
  const auto result = desktop_app_->engine().Forward(*lease, nullptr, std::chrono::seconds(2));
  if (!result.ok && shell_) shell_->ShowToast(utf::Utf8ToWideDisplay(result.message));
}

void WindowsApp::OnReloadRequested() {
  const auto lease = ActiveLease(desktop_app_.get());
  if (!lease) return;
  const auto result = browser_state_.is_loading
      ? desktop_app_->engine().StopLoading(*lease, nullptr, std::chrono::seconds(2))
      : desktop_app_->engine().Reload(*lease, nullptr, std::chrono::seconds(2));
  if (!result.ok && shell_) shell_->ShowToast(utf::Utf8ToWideDisplay(result.message));
}

void WindowsApp::OnOpenSettingsRequested() {
  SettingsValues updated = CurrentSettings();
  if (settings_view_->ShowModal(instance_, shell_->hwnd(), CurrentSettings(), updated)) {
    ApplySettings(updated);
  }
}

std::string WindowsApp::GetBookmarksJson() const {
  return account_ ? account_->Bookmarks() : desktop_app_ ? desktop_app_->bookmark_store().ToJson() : "[]";
}

std::string WindowsApp::GetHistoryJson() const {
  return desktop_app_ ? desktop_app_->history_store().ToJson() : "[]";
}

std::string WindowsApp::GetNetworkJson() const {
  return desktop_app_ ? desktop_app_->network_store().ToJson() : "[]";
}

std::string WindowsApp::GetTabsJson() const {
  if (!desktop_app_) return R"({"tabs":[]})";
  std::vector<TabSnapshot> tabs;
  if (!desktop_app_->engine().GetTabs(&tabs, std::chrono::seconds(2)).ok) return R"({"tabs":[]})";
  json items = json::array();
  for (const auto& tab : tabs) {
    json entry = {{"id", tab.id}, {"generation", tab.generation}, {"title", tab.title},
                  {"url", tab.url}, {"active", tab.active}, {"isStartPage", tab.is_start_page},
                  {"favicon", tab.favicon_png_base64 ? *tab.favicon_png_base64 : ""}};
    // The shell prints `name` instead of the title and marks a partitioned
    // pill, so both have to reach it.
    if (tab.name) entry["name"] = *tab.name;
    if (tab.partition) entry["partition"] = *tab.partition;
    if (tab.persistent) entry["persistent"] = *tab.persistent;
    items.push_back(std::move(entry));
  }
  return json{{"tabs", items}}.dump();
}

std::optional<std::wstring> WindowsApp::BestUrlCompletion(std::wstring_view typed) const {
  const auto utf8 = utf::WideToUtf8(typed);
  if (!utf8 || utf8->empty()) return std::nullopt;
  const std::string completion = desktop_app_ ? desktop_app_->history_store().BestUrlCompletion(*utf8) : std::string();
  if (completion.empty()) return std::nullopt;
  return utf::Utf8ToWide(completion);
}

void WindowsApp::OnCreateTabRequested() {
  CreateTabFromShell(config_.isolate_new_tabs);
}

void WindowsApp::OnCreateIsolatedTabRequested() {
  CreateTabFromShell(true);
}

void WindowsApp::CreateTabFromShell(bool isolated) {
  if (!desktop_app_) return;
  NewTabRequest request;
  if (isolated) {
    const std::string partition = NewIsolatedPartitionId();
    if (partition.empty()) {
      if (shell_) shell_->ShowToast(L"Could not allocate an isolated partition");
      return;
    }
    request.partition = partition;
  }
  TabSnapshot tab;
  // No URL in the request: the engine opens the start page, the same default
  // the HTTP and MCP `new-tab` commands get.
  const auto result = desktop_app_->engine().CreateTab(request, &tab, std::chrono::seconds(5));
  if (result.ok) { desktop_app_->engine().ActivateTab({tab.id, tab.generation}, std::chrono::seconds(2)); SaveSession(); }
  else if (shell_) shell_->ShowToast(utf::Utf8ToWideDisplay(result.message));
}

void WindowsApp::OnActivateTabRequested(std::string id, std::uint64_t generation) {
  if (!desktop_app_) return;
  const auto result = desktop_app_->engine().ActivateTab({std::move(id), generation}, std::chrono::seconds(2));
  if (result.ok) SaveSession();
  if (!result.ok && shell_) shell_->ShowToast(utf::Utf8ToWideDisplay(result.message));
}

void WindowsApp::OnCloseTabRequested(std::string id, std::uint64_t generation) {
  if (!desktop_app_) return;
  const auto result = desktop_app_->engine().CloseTab({std::move(id), generation}, std::chrono::seconds(5));
  if (result.ok) SaveSession();
  if (!result.ok && shell_) shell_->ShowToast(utf::Utf8ToWideDisplay(result.message));
}

SettingsValues WindowsApp::CurrentSettings() const {
  return SettingsValues{
      config_.port,
      config_.profile_dir.wstring(),
      utf::Utf8ToWideDisplay(config_.initial_url),
      config_.isolate_new_tabs,
  };
}

void WindowsApp::PersistForClose() {
  // Persist while the engine-owned stores and tab model still exist. This runs
  // only after the HTTP listener has retired every handler it admitted before
  // close, so no acknowledged mutation can be written after this snapshot.
  SaveSession();
  SaveStores();
  if (shell_ != nullptr) {
    if (auto placement = CaptureWindowPlacement(shell_->hwnd())) window_placement_ = placement;
  }
  SaveSettings();
}

void WindowsApp::ArmCloseRetry() {
  if (shell_ != nullptr && shell_->hwnd() != nullptr) {
    SetTimer(shell_->hwnd(), kCloseRetryTimerId, 50, nullptr);
  }
}

bool WindowsApp::TryCompleteClose() {
  if (!close_lifecycle_.requested() || close_lifecycle_.completed()) {
    return close_lifecycle_.completed();
  }
  if (desktop_app_ != nullptr) {
    desktop_app_->BeginShutdown();
    if (!desktop_app_->IsShutdownReady()) {
      ArmCloseRetry();
      return false;
    }
  }
  const bool completed = close_lifecycle_.Advance(
      true, [this] { PersistForClose(); }, [this] { return ShutdownDesktopRuntime(); });
  if (!completed) {
    ArmCloseRetry();
    return false;
  }
  if (shell_ != nullptr && shell_->hwnd() != nullptr) {
    KillTimer(shell_->hwnd(), kCloseRetryTimerId);
  }
  running_ = false;
  if (shell_ != nullptr) shell_->Close();
  return true;
}

void WindowsApp::OnWindowCloseRequested() {
  if (account_) account_->Shutdown();
  close_lifecycle_.Request();
  if (desktop_app_ != nullptr) desktop_app_->BeginShutdown();
  TryCompleteClose();
}
void WindowsApp::OnBrowserStateChanged(const BrowserState& state) {
  browser_state_ = state;
  shell_->UpdateBrowserState(state);
}


void WindowsApp::ApplySettings(const SettingsValues& settings) {
  config_.initial_url = utf::WideToUtf8(settings.startup_url).value_or(config_.initial_url);
  config_.isolate_new_tabs = settings.isolate_new_tabs;
  SaveSettings();
  shell_->ShowToast(L"Settings saved");
}

bool WindowsApp::InitializeCommonControls() const {
  INITCOMMONCONTROLSEX controls{};
  controls.dwSize = sizeof(controls);
  controls.dwICC = ICC_LISTVIEW_CLASSES | ICC_STANDARD_CLASSES | ICC_TAB_CLASSES;
  return InitCommonControlsEx(&controls) != FALSE;
}

bool WindowsApp::CreateShell(int show_command) {
  // The remembered position is reused only while it still lands on a connected
  // monitor at the size being opened; otherwise Windows places the window.
  std::optional<POINT> origin;
  if (window_placement_) {
    const POINT saved{window_placement_->frame.left, window_placement_->frame.top};
    const RECT frame{saved.x, saved.y, saved.x + config_.width, saved.y + config_.height};
    if (WindowFrameIsUsable(frame, MonitorWorkAreas())) origin = saved;
  }
  if (!shell_->Create(AppTitle(), config_.width, config_.height, origin)) {
    return false;
  }
  // SW_SHOWDEFAULT defers to the launcher's STARTUPINFO, which may hide or
  // minimize the window; only a plain visible launch restores maximized.
  int requested = show_command;
  if (requested == SW_SHOWDEFAULT) {
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    GetStartupInfoW(&startup);
    requested = (startup.dwFlags & STARTF_USESHOWWINDOW) != 0 ? startup.wShowWindow : SW_SHOWNORMAL;
  }
  const bool normal_launch = requested == SW_SHOWNORMAL || requested == SW_SHOW;
  shell_->Show(window_placement_ && window_placement_->maximized && normal_launch ? SW_SHOWMAXIMIZED
                                                                                 : show_command);
  return true;
}

std::wstring WindowsApp::AppTitle() const {
  return L"Kelpie";
}

}  // namespace kelpie::windows
