#include "windows_app.h"

#include "kelpie/desktop_http_server.h"
#include "windows_utf.h"

#include <commctrl.h>

#include <fstream>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <shlobj.h>

#if defined(HAS_CEF)
#include "include/cef_app.h"
#include "kelpie/cef_app_factory.h"
#endif

namespace kelpie::windows {
namespace {

constexpr UINT_PTR kCefPumpTimerId = 0x4B50;

void CALLBACK PumpCefTimer(HWND, UINT, UINT_PTR timer_id, DWORD) {
#if defined(HAS_CEF)
  KillTimer(nullptr, timer_id);
  CefDoMessageLoopWork();
#endif
}

std::optional<TabLease> ActiveLease(DesktopApp* app) {
  if (app == nullptr) return std::nullopt;
  std::vector<TabSnapshot> tabs;
  if (!app->engine().GetTabs(&tabs, std::chrono::seconds(2)).ok) return std::nullopt;
  for (const auto& tab : tabs) if (tab.active) return TabLease{tab.id, tab.generation};
  return std::nullopt;
}

bool HasScheme(const std::string& value) {
  const auto colon = value.find(':');
  return colon != std::string::npos && colon > 0 &&
      std::all_of(value.begin(), value.begin() + static_cast<std::ptrdiff_t>(colon), [](unsigned char c) {
        return std::isalnum(c) || c == '+' || c == '-' || c == '.';
      });
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

void SaveJsonFile(const std::filesystem::path& path, const nlohmann::json& value) {
  std::filesystem::create_directories(path.parent_path());
  std::ofstream output(path, std::ios::trunc);
  output << value.dump(2);
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
  if (!profile_session_.Open(config_.profile_dir, config_.readiness_path, &session_error)) return 1;
  LoadSettings();
  LoadStores();
  if (!InitializeCommonControls()) return 1;
  if (!CreateShell(show_command)) return 1;
  if (!InitializeDesktopRuntime()) return 1;

  MSG message{};
  while (running_ && GetMessageW(&message, nullptr, 0, 0) > 0) {
    if (shell_ == nullptr || !TranslateAcceleratorW(shell_->hwnd(), shell_->accelerators(), &message)) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
    desktop_app_->Tick();
    UpdateBrowserStateFromRuntime();
  }

  SaveStores();
  SaveSettings();
  ShutdownDesktopRuntime();
  return 0;
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
  const auto result = desktop_app_->engine().Reload(*lease, nullptr, std::chrono::seconds(2));
  if (!result.ok && shell_) shell_->ShowToast(utf::Utf8ToWideDisplay(result.message));
}

void WindowsApp::OnOpenSettingsRequested() {
  SettingsValues updated = CurrentSettings();
  if (settings_view_->ShowModal(instance_, shell_->hwnd(), CurrentSettings(), updated)) {
    ApplySettings(updated);
  }
}

std::string WindowsApp::GetBookmarksJson() const {
  return bookmark_store_.ToJson();
}

std::string WindowsApp::GetHistoryJson() const {
  return history_store_.ToJson();
}

std::string WindowsApp::GetNetworkJson() const {
  return network_store_.ToJson();
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
  const std::string completion = history_store_.BestUrlCompletion(*utf8);
  if (completion.empty()) return std::nullopt;
  return utf::Utf8ToWide(completion);
}

void WindowsApp::OnCreateTabRequested() {
  if (!desktop_app_) return;
  TabSnapshot tab;
  const auto result = desktop_app_->engine().CreateTab("about:blank", &tab, std::chrono::seconds(5));
  if (result.ok) desktop_app_->engine().ActivateTab({tab.id, tab.generation}, std::chrono::seconds(2));
  else if (shell_) shell_->ShowToast(utf::Utf8ToWideDisplay(result.message));
}

void WindowsApp::OnActivateTabRequested(std::string id, std::uint64_t generation) {
  if (!desktop_app_) return;
  const auto result = desktop_app_->engine().ActivateTab({std::move(id), generation}, std::chrono::seconds(2));
  if (!result.ok && shell_) shell_->ShowToast(utf::Utf8ToWideDisplay(result.message));
}

void WindowsApp::OnCloseTabRequested(std::string id, std::uint64_t generation) {
  if (!desktop_app_) return;
  const auto result = desktop_app_->engine().CloseTab({std::move(id), generation}, std::chrono::seconds(5));
  if (!result.ok && shell_) shell_->ShowToast(utf::Utf8ToWideDisplay(result.message));
}

SettingsValues WindowsApp::CurrentSettings() const {
  return SettingsValues{
      config_.port,
      config_.profile_dir.wstring(),
      utf::Utf8ToWideDisplay(config_.initial_url),
  };
}

void WindowsApp::OnWindowCloseRequested() {
  running_ = false;
}

void WindowsApp::OnBrowserStateChanged(const BrowserState& state) {
  browser_state_ = state;
  shell_->UpdateBrowserState(state);
  RememberNavigation(state);
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
  SaveJsonFile(config_.profile_dir / "settings.json",
               {
                   {"port", config_.port},
                   {"profile_dir", config_.profile_dir.u8string()},
                   {"startup_url", config_.initial_url},
               });
}

void WindowsApp::LoadStores() {
  nlohmann::json bookmarks;
  if (LoadJsonFile(config_.profile_dir / "bookmarks.json", bookmarks)) {
    bookmark_store_.LoadJson(bookmarks.dump());
  }
  nlohmann::json history;
  if (LoadJsonFile(config_.profile_dir / "history.json", history)) {
    history_store_.LoadJson(history.dump());
  }
}

void WindowsApp::SaveStores() const {
  SaveJsonFile(config_.profile_dir / "bookmarks.json",
               nlohmann::json::parse(bookmark_store_.ToJson(), nullptr, false));
  SaveJsonFile(config_.profile_dir / "history.json",
               nlohmann::json::parse(history_store_.ToJson(), nullptr, false));
}

void WindowsApp::ApplySettings(const SettingsValues& settings) {
  config_.initial_url = utf::WideToUtf8(settings.startup_url).value_or(config_.initial_url);
  SaveSettings();
  const bool restart_required = settings.port != config_.port ||
      (!settings.profile_dir.empty() && std::filesystem::path(settings.profile_dir) != config_.profile_dir);
  shell_->ShowToast(restart_required ? L"Startup URL saved. Restart Kelpie to change profile or port."
                                    : L"Settings saved");
}

bool WindowsApp::InitializeCommonControls() const {
  INITCOMMONCONTROLSEX controls{};
  controls.dwSize = sizeof(controls);
  controls.dwICC = ICC_LISTVIEW_CLASSES | ICC_STANDARD_CLASSES | ICC_TAB_CLASSES;
  return InitCommonControlsEx(&controls) != FALSE;
}

bool WindowsApp::InitializeDesktopRuntime() {
  SetDesktopCefMessagePumpScheduler([](std::int64_t delay_ms) {
    const UINT delay = static_cast<UINT>(std::clamp<std::int64_t>(delay_ms, 1, 60'000));
    SetTimer(nullptr, kCefPumpTimerId, delay, &PumpCefTimer);
  });
  desktop_app_ = std::make_unique<DesktopApp>();
  DesktopApp::Config runtime;
  runtime.platform = Platform::kWindows;
  runtime.engine_name = "chromium";
  runtime.port = config_.port;
  runtime.app_name = "kelpie";
  runtime.app_version = "0.1.1";
  runtime.start_stdio_mcp = config_.mcp_stdio;
  runtime.bind_host = "127.0.0.1";
  runtime.control_token = profile_session_.token();
  runtime.device_id = device_info_provider_.Collect(config_.port, config_.width, config_.height, runtime.app_version).id;
  runtime.engine.mode = DesktopEngine::Mode::kWindowed;
  runtime.engine.process_instance = config_.cef_process_instance;
  runtime.engine.sandbox_info = config_.sandbox_info;
  runtime.engine.initial_url = config_.initial_url;
  runtime.engine.cache_path = utf::WideToUtf8((config_.profile_dir / "cache").wstring()).value_or(std::string());
  runtime.engine.configure_window_info = [this](void* raw_info) {
    auto* info = static_cast<CefWindowInfo*>(raw_info);
    RECT rect{};
    GetClientRect(browser_view_->hwnd(), &rect);
    info->SetAsChild(browser_view_->hwnd(), CefRect(0, 0, rect.right, rect.bottom));
  };
  runtime.engine.configure_tab_window_info = [this](void* raw_info, const std::string&) {
    auto* info = static_cast<CefWindowInfo*>(raw_info);
    RECT rect{};
    GetClientRect(browser_view_->hwnd(), &rect);
    info->SetAsChild(browser_view_->hwnd(), CefRect(0, 0, rect.right, rect.bottom));
  };
  if (!desktop_app_->Start(runtime)) {
    desktop_app_.reset();
    return false;
  }
  browser_view_->ShowFallback(false);
  std::string readiness_error;
  if (!profile_session_.PublishReadiness(runtime.device_id, desktop_app_->http_server().bound_port(),
                                         runtime.start_stdio_mcp, &readiness_error)) {
    ShutdownDesktopRuntime();
    return false;
  }
  return true;
}

void WindowsApp::ShutdownDesktopRuntime() {
  KillTimer(nullptr, kCefPumpTimerId);
  SetDesktopCefMessagePumpScheduler({});
  if (desktop_app_) {
    desktop_app_->Stop();
    desktop_app_.reset();
  }
  profile_session_.ClearReadiness();
}

void WindowsApp::UpdateBrowserStateFromRuntime() {
  if (!desktop_app_) return;
  std::vector<TabSnapshot> tabs;
  if (!desktop_app_->engine().GetTabs(&tabs, std::chrono::milliseconds(20)).ok) return;
  for (const auto& tab : tabs) {
    if (tab.active) {
      OnBrowserStateChanged({tab.url, tab.title, tab.is_loading, tab.can_go_back, tab.can_go_forward});
      return;
    }
  }
}

bool WindowsApp::CreateShell(int show_command) {
  if (!shell_->Create(AppTitle(), config_.width, config_.height)) {
    return false;
  }
  shell_->Show(show_command);
  return true;
}

void WindowsApp::RememberNavigation(const BrowserState& state) {
  if (state.url.empty()) {
    return;
  }
  history_store_.Record(state.url, state.title);
  history_store_.UpdateLatestTitle(state.url, state.title);
  if (state.url != last_recorded_url_) {
    network_store_.AppendDocumentNavigation(state.url, 200, "text/html");
    last_recorded_url_ = state.url;
  }
}

std::wstring WindowsApp::AppTitle() const {
  return L"Kelpie";
}

}  // namespace kelpie::windows
