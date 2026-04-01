#include "windows_app.h"

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
#endif

namespace mollotov::windows {
namespace {

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return {};
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  std::wstring output(static_cast<std::size_t>(size > 0 ? size - 1 : 0), L'\0');
  if (size > 1) {
    MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, output.data(), size - 1);
  }
  return output;
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return {};
  }
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, nullptr, 0, nullptr, nullptr);
  std::string output(static_cast<std::size_t>(size > 0 ? size - 1 : 0), '\0');
  if (size > 1) {
    WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, output.data(), size - 1, nullptr, nullptr);
  }
  return output;
}

std::filesystem::path RoamingAppDataPath() {
  wchar_t buffer[MAX_PATH]{};
  if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_APPDATA, nullptr, SHGFP_TYPE_CURRENT, buffer))) {
    return std::filesystem::path(buffer) / "Mollotov";
  }
  return std::filesystem::temp_directory_path() / "Mollotov";
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

#if defined(HAS_CEF)
class WindowsCefApp final : public CefApp {
 public:
  IMPLEMENT_REFCOUNTING(WindowsCefApp);
};
#endif

}  // namespace

WindowsApp::WindowsApp(HINSTANCE instance, AppConfig config)
    : instance_(instance),
      config_(std::move(config)),
      handler_context_(nullptr),
      device_info_provider_(config_.profile_dir),
      browser_view_(std::make_unique<Win32BrowserView>()),
      settings_view_(std::make_unique<SettingsView>()),
      mdns_(std::make_unique<MdnsWindows>()) {
  handler_context_.SetRenderer(browser_view_.get());
  shell_ = std::make_unique<Win32Shell>(instance_, this, this, browser_view_.get());
}

WindowsApp::~WindowsApp() {
  StopHttpServer();
  StopMdns();
  ShutdownBrowserRuntime();
}

int WindowsApp::Run(int show_command) {
  ResolveProfileDirectory();
  LoadSettings();
  LoadStores();
  if (!InitializeCommonControls()) {
    return 1;
  }
  if (!InitializeBrowserRuntime()) {
    return 1;
  }
  const bool has_shell = CreateShell(show_command);
  if (!has_shell) {
    // Shell creation failed (e.g. running under Wine without a display driver).
    // Continue anyway so the HTTP server is still accessible.
  }

  browser_view_->LoadUrl(config_.initial_url);
  RefreshDeviceInfo();
  StartHttpServer();
  StartMdns();

  if (has_shell) {
    MSG message{};
    while (running_ && GetMessageW(&message, nullptr, 0, 0) > 0) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
#if defined(HAS_CEF)
      CefDoMessageLoopWork();
#endif
    }
  } else {
    // No message loop — run headless-style until shutdown is requested.
    while (running_) {
      Sleep(100);
    }
  }

  SaveStores();
  SaveSettings();
  StopHttpServer();
  StopMdns();
  ShutdownBrowserRuntime();
  return 0;
}

void WindowsApp::OnNavigateRequested(const std::string& url) {
  std::string resolved = url;
  if (resolved.find("://") == std::string::npos) {
    resolved = "https://" + resolved;
  }
  browser_view_->LoadUrl(resolved);
}

void WindowsApp::OnBackRequested() {
  browser_view_->GoBack();
}

void WindowsApp::OnForwardRequested() {
  browser_view_->GoForward();
}

void WindowsApp::OnReloadRequested() {
  browser_view_->Reload();
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

SettingsValues WindowsApp::CurrentSettings() const {
  return SettingsValues{
      config_.port,
      config_.profile_dir.wstring(),
      Utf8ToWide(config_.initial_url),
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
  config_.port = settings.port;
  if (!settings.profile_dir.empty()) {
    config_.profile_dir = settings.profile_dir;
    std::filesystem::create_directories(config_.profile_dir);
    device_info_provider_.SetProfileDir(config_.profile_dir);
  }
  config_.initial_url = WideToUtf8(settings.startup_url);
  SaveSettings();
  RefreshDeviceInfo();
  StopHttpServer();
  StopMdns();
  StartHttpServer();
  StartMdns();
  shell_->ShowToast(L"Settings saved");
}

bool WindowsApp::InitializeCommonControls() const {
  INITCOMMONCONTROLSEX controls{};
  controls.dwSize = sizeof(controls);
  controls.dwICC = ICC_LISTVIEW_CLASSES | ICC_STANDARD_CLASSES;
  return InitCommonControlsEx(&controls) != FALSE;
}

bool WindowsApp::InitializeBrowserRuntime() {
#if defined(HAS_CEF)
  CefMainArgs main_args(instance_);
  CefRefPtr<WindowsCefApp> app(new WindowsCefApp());
  if (const int exit_code = CefExecuteProcess(main_args, app, nullptr); exit_code >= 0) {
    return false;
  }
  CefSettings settings;
  settings.no_sandbox = true;
  settings.windowless_rendering_enabled = false;
  CefString(&settings.cache_path) = config_.profile_dir.wstring() + L"\\cache";
  return CefInitialize(main_args, settings, app, nullptr);
#else
  return true;
#endif
}

void WindowsApp::ShutdownBrowserRuntime() {
#if defined(HAS_CEF)
  CefShutdown();
#endif
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

void WindowsApp::RefreshDeviceInfo() {
  device_info_ = BuildDeviceInfo();
}

std::wstring WindowsApp::AppTitle() const {
  return L"Mollotov";
}

}  // namespace mollotov::windows
