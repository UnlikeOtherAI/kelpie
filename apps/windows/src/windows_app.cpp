#include "windows_app.h"

#include "windows_utf.h"

#include <commctrl.h>

#include <algorithm>
#include <cctype>
#include <thread>

#include <fstream>
#include <atomic>
#include <limits>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <shlobj.h>


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
std::filesystem::path RoamingAppDataPath() {
  wchar_t buffer[MAX_PATH]{};
  if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_APPDATA, nullptr, SHGFP_TYPE_CURRENT, buffer))) {
    return std::filesystem::path(buffer) / "Kelpie";
  }
  return std::filesystem::temp_directory_path() / "Kelpie";
}

bool LoadJsonFile(const std::filesystem::path& path, nlohmann::json& output) {
  std::ifstream input(path);
  if (!input.good()) {
    return false;
  }
  try {
    input >> output;
    return true;
  } catch (...) {
    output = nlohmann::json::object();
    return false;
  }
}

bool SaveJsonFileAtomically(const std::filesystem::path& path, const nlohmann::json& value,
                          std::uint64_t epoch) {
  std::error_code error;
  std::filesystem::create_directories(path.parent_path(), error);
  if (error) return false;
  const std::filesystem::path temporary = path.wstring() + L".tmp." + std::to_wstring(epoch);
  {
    std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
    if (!output.good()) return false;
    output << value.dump(2);
    output.flush();
    if (!output.good()) return false;
  }
  HANDLE handle = CreateFileW(temporary.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                              OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (handle == INVALID_HANDLE_VALUE) return false;
  const bool flushed = FlushFileBuffers(handle) != FALSE;
  CloseHandle(handle);
  if (!flushed) return false;
  if (!MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    DeleteFileW(temporary.c_str());
    return false;
  }
  return true;
}

bool SameSession(const SessionSnapshot& left, const SessionSnapshot& right) {
  if (left.next_tab_id != right.next_tab_id || left.tabs.size() != right.tabs.size()) return false;
  for (std::size_t index = 0; index < left.tabs.size(); ++index) {
    const SessionTab& a = left.tabs[index];
    const SessionTab& b = right.tabs[index];
    if (a.id != b.id || a.url != b.url || a.active != b.active) return false;
  }
  return true;
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
  ShutdownDesktopRuntime();
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
  return desktop_app_ ? desktop_app_->bookmark_store().ToJson() : "[]";
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
    items.push_back({{"id", tab.id}, {"generation", tab.generation}, {"title", tab.title},
                     {"url", tab.url}, {"active", tab.active}});
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
  if (!desktop_app_) return;
  TabSnapshot tab;
  const auto result = desktop_app_->engine().CreateTab("about:blank", &tab, std::chrono::seconds(5));
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
  };
}

void WindowsApp::PersistForClose() {
  // Persist while the engine-owned stores and tab model still exist. This runs
  // only after the HTTP listener has retired every handler it admitted before
  // close, so no acknowledged mutation can be written after this snapshot.
  SaveSession();
  SaveStores();
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
  close_lifecycle_.Request();
  if (desktop_app_ != nullptr) desktop_app_->BeginShutdown();
  TryCompleteClose();
}
void WindowsApp::OnBrowserStateChanged(const BrowserState& state) {
  browser_state_ = state;
  shell_->UpdateBrowserState(state);
}

void WindowsApp::ResolveProfileDirectory() {
  if (config_.profile_dir.empty()) {
    config_.profile_dir = RoamingAppDataPath();
  }
  std::filesystem::create_directories(config_.profile_dir);
  device_info_provider_.SetProfileDir(config_.profile_dir);
}

void WindowsApp::LoadSettings() {
  nlohmann::json settings;
  if (!LoadJsonFile(config_.profile_dir / "settings.json", settings)) {
    return;
  }
  if (!config_.port_overridden) {
    config_.port = settings.value("port", config_.port);
  }
  if (!config_.url_overridden) {
    config_.initial_url = settings.value("startup_url", config_.initial_url);
  }
}

void WindowsApp::SaveSettings() const {
  SaveJsonFileAtomically(config_.profile_dir / "settings.json",
                         {{"port", config_.port}, {"profile_dir", config_.profile_dir.u8string()},
                          {"startup_url", config_.initial_url}}, persistence_epoch_ + 1);
}


void WindowsApp::LoadSession() {
  nlohmann::json value;
  if (!LoadJsonFile(config_.profile_dir / "session.json", value)) return;
  SessionSnapshot parsed;
  if (ParseSessionSnapshot(value, &parsed)) session_snapshot_ = std::move(parsed);
}

void WindowsApp::SaveSession() {
  if (!desktop_app_) return;
  DesktopEngine::SessionState state;
  if (!desktop_app_->engine().GetSessionState(&state, std::chrono::seconds(2)).ok || state.tabs.empty()) return;
  if (session_snapshot_.epoch == std::numeric_limits<std::uint64_t>::max()) return;
  SessionSnapshot next;
  next.epoch = session_snapshot_.epoch + 1;
  next.next_tab_id = state.next_tab_id;
  for (const auto& tab : state.tabs) next.tabs.push_back({tab.id, tab.url, tab.active});
  if (SameSession(session_snapshot_, next)) return;
  if (SaveJsonFileAtomically(config_.profile_dir / "session.json", SerializeSessionSnapshot(next), next.epoch)) session_snapshot_ = std::move(next);
}

void WindowsApp::LoadStores() {
  nlohmann::json epoch;
  if (LoadJsonFile(config_.profile_dir / "stores-epoch.json", epoch)) {
    persistence_epoch_ = epoch.value("epoch", std::uint64_t{0});
  }
  // The exclusive ProfileSession lock is held before this method runs. Legacy
  // files remain readable; all later writes are atomic replacements by this owner.
  if (!desktop_app_) return;
  nlohmann::json bookmarks;
  if (LoadJsonFile(config_.profile_dir / "bookmarks.json", bookmarks)) {
    desktop_app_->bookmark_store().LoadJson(bookmarks.dump());
  }
  nlohmann::json history;
  if (LoadJsonFile(config_.profile_dir / "history.json", history)) {
    desktop_app_->history_store().LoadJson(history.dump());
  }
}

void WindowsApp::SaveStores() {
  if (!desktop_app_) return;
  const std::uint64_t next_epoch = persistence_epoch_ + 1;
  const auto bookmarks = nlohmann::json::parse(desktop_app_->bookmark_store().ToJson(), nullptr, false);
  const auto history = nlohmann::json::parse(desktop_app_->history_store().ToJson(), nullptr, false);
  if (bookmarks.is_discarded() || history.is_discarded()) return;
  if (!SaveJsonFileAtomically(config_.profile_dir / "bookmarks.json", bookmarks, next_epoch) ||
      !SaveJsonFileAtomically(config_.profile_dir / "history.json", history, next_epoch)) return;
  if (SaveJsonFileAtomically(config_.profile_dir / "stores-epoch.json", {{"epoch", next_epoch}}, next_epoch)) {
    persistence_epoch_ = next_epoch;
  }
}

void WindowsApp::ApplySettings(const SettingsValues& settings) {
  config_.initial_url = utf::WideToUtf8(settings.startup_url).value_or(config_.initial_url);
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
  if (!shell_->Create(AppTitle(), config_.width, config_.height)) {
    return false;
  }
  shell_->Show(show_command);
  return true;
}

std::wstring WindowsApp::AppTitle() const {
  return L"Kelpie";
}

}  // namespace kelpie::windows
