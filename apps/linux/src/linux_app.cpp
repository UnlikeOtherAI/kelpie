#include "linux_app.h"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <utility>

#include "gui_shell.h"
#include "headless_shell.h"
#include "linux_app_internal.h"

#if MOLLOTOV_LINUX_HAS_CEF
#include "include/cef_app.h"
#endif

namespace mollotov::linuxapp {

namespace {

constexpr const char* kDefaultHomeUrl = "https://unlikeotherai.github.io/mollotov";

std::filesystem::path CurrentExecutablePath() {
  std::error_code error;
  const std::filesystem::path path = std::filesystem::read_symlink("/proc/self/exe", error);
  return error ? std::filesystem::path() : path;
}

std::filesystem::path HomeUrlPath(const std::string& profile_dir) {
  return std::filesystem::path(profile_dir) / "home_url.txt";
}

std::string NormalizeHomeUrl(const std::string& url) {
  return url.empty() ? std::string(kDefaultHomeUrl) : url;
}

std::string LoadHomeUrl(const std::string& profile_dir) {
  const std::string saved = ReadTextFile(HomeUrlPath(profile_dir));
  if (saved.empty()) {
    return std::string(kDefaultHomeUrl);
  }
  std::string trimmed = saved;
  while (!trimmed.empty() && (trimmed.back() == '\n' || trimmed.back() == '\r')) {
    trimmed.pop_back();
  }
  return NormalizeHomeUrl(trimmed);
}

void PersistHomeUrl(const std::string& profile_dir, const std::string& url) {
  WriteTextFile(HomeUrlPath(profile_dir), NormalizeHomeUrl(url));
}

std::string InitialUrl(const AppConfig& config) {
  return NormalizeHomeUrl(config.url);
}

#if MOLLOTOV_LINUX_HAS_CEF
mollotov::DesktopEngine::Config BuildDesktopEngineConfig(const AppConfig& config,
                                                         int argc,
                                                         char** argv,
                                                         mollotov::DesktopEngine::Mode mode) {
  mollotov::DesktopEngine::Config engine_config;
  const std::filesystem::path executable_path = CurrentExecutablePath();
  const std::filesystem::path executable_dir = executable_path.parent_path();
  engine_config.mode = mode;
  engine_config.viewport.width = config.width;
  engine_config.viewport.height = config.height;
  engine_config.argc = argc;
  engine_config.argv = argv;
  engine_config.initial_url = InitialUrl(config);
  engine_config.cache_path = config.profile_dir + "/cef-cache";
  engine_config.browser_subprocess_path = executable_path.string();
  engine_config.resources_dir_path = executable_dir.string();
  engine_config.locales_dir_path = (executable_dir / "locales").string();
  engine_config.external_message_pump = true;
  return engine_config;
}
#endif

}  // namespace

std::string ReadTextFile(const std::filesystem::path& path) {
  std::ifstream stream(path);
  if (!stream.good()) {
    return std::string();
  }
  std::ostringstream buffer;
  buffer << stream.rdbuf();
  return buffer.str();
}

void WriteTextFile(const std::filesystem::path& path, const std::string& contents) {
  std::filesystem::create_directories(path.parent_path());
  std::ofstream stream(path, std::ios::trunc);
  stream << contents;
}

std::string CategoryForFilter(const nlohmann::json& entry) {
  return entry.value("category", "Other");
}

LinuxApp::Impl::Impl(AppConfig app_config, int argc_value, char** argv_value)
    : config(std::move(app_config)),
      argc(argc_value),
      argv(argv_value),
      stub_renderer(std::make_unique<StubRenderer>(config.url)),
      renderer(stub_renderer.get()),
      handler_context(renderer),
      device_info(config.profile_dir) {}

void LinuxApp::Impl::LoadStores() {
  const std::filesystem::path root(config.profile_dir);
  bookmarks.LoadJson(ReadTextFile(root / "bookmarks.json"));
  history.LoadJson(ReadTextFile(root / "history.json"));
  console.LoadJson(ReadTextFile(root / "console.json"));
  network.LoadJson(ReadTextFile(root / "network.json"));
}

void LinuxApp::Impl::PersistStores() const {
  const std::filesystem::path root(config.profile_dir);
  WriteTextFile(root / "bookmarks.json", bookmarks.ToJson());
  WriteTextFile(root / "history.json", history.ToJson());
  WriteTextFile(root / "console.json", console.ToJson());
  WriteTextFile(root / "network.json", network.ToJson());
}

void LinuxApp::Impl::RecordNavigation(const std::string& url) {
  history.Record(url, renderer->CurrentTitle());
  network.AppendDocumentNavigation(url, 200, "text/html");
  PersistStores();
}

LinuxApp::LinuxApp(AppConfig config, int argc, char* argv[])
    : impl_([&config, argc, argv]() {
        if (config.url.empty()) {
          config.url = LoadHomeUrl(config.profile_dir);
        }
        return std::make_unique<Impl>(std::move(config), argc, argv);
      }()) {
  impl_->LoadStores();
  if (!impl_->config.url.empty()) {
    impl_->RecordNavigation(impl_->config.url);
  }
}

LinuxApp::~LinuxApp() = default;

int LinuxApp::Run() {
#if MOLLOTOV_LINUX_HAS_CEF
  if (impl_->config.headless) {
    mollotov::DesktopEngine::Config engine_config =
        BuildDesktopEngineConfig(
            impl_->config, impl_->argc, impl_->argv, mollotov::DesktopEngine::Mode::kOffscreen);
    if (impl_->desktop_engine.Initialize(engine_config)) {
      impl_->renderer = &impl_->desktop_engine.renderer();
      impl_->handler_context.SetRenderer(impl_->renderer);
      impl_->browser_initialized = true;
    } else {
      std::cerr << "CEF runtime unavailable; continuing with stub renderer.\n";
    }
  }
#endif

  std::string error;
  if (!impl_->http_server.Start(
          impl_->config.port,
          [this](std::string_view endpoint, const json& params, int* status) {
            return HandleApiRequest(endpoint, params, status);
          },
          &error)) {
    std::cerr << "Failed to start HTTP server: " << error << '\n';
    return 1;
  }
  impl_->bound_port = impl_->http_server.port();

  const DeviceInfoSnapshot snapshot = impl_->device_info.Collect();
  const bool mdns_started = impl_->mdns.Start(MdnsServiceConfig{
      snapshot,
      impl_->bound_port,
      impl_->config.width,
      impl_->config.height,
      impl_->version,
      RuntimeMode(),
  });
  impl_->mdns_status = mdns_started ? "active" : impl_->mdns.LastError();
  impl_->running = true;

  if (impl_->config.headless) {
    HeadlessShell shell(*this);
    const int result = shell.Run();
    impl_->running = false;
    impl_->mdns.Stop();
    impl_->http_server.Stop();
    impl_->desktop_engine.Shutdown();
    impl_->PersistStores();
    return result;
  }

  if (!GuiAvailable()) {
    std::cerr << "GTK3 support is not available in this build. Rebuild with GTK or use --headless.\n";
    impl_->running = false;
    impl_->mdns.Stop();
    impl_->http_server.Stop();
    return 1;
  }

  GUIShell shell(*this);
  const int result = shell.Run();
  impl_->running = false;
  impl_->mdns.Stop();
  impl_->http_server.Stop();
  impl_->desktop_engine.Shutdown();
  impl_->PersistStores();
  return result;
}

void LinuxApp::RequestShutdown() {
  impl_->shutdown_requested = true;
  impl_->running = false;
}

bool LinuxApp::IsRunning() const {
  return impl_->running && !impl_->shutdown_requested;
}

void LinuxApp::PumpBrowser() {
  impl_->desktop_engine.DoMessageLoopWork();
}

bool LinuxApp::AttachBrowserHost(std::uintptr_t parent_window, int width, int height) {
#if MOLLOTOV_LINUX_HAS_CEF
  (void)parent_window;
  if (impl_->browser_initialized) {
    ResizeBrowserHost(width, height);
    return true;
  }

  mollotov::DesktopEngine::Config engine_config =
      BuildDesktopEngineConfig(
          impl_->config, impl_->argc, impl_->argv, mollotov::DesktopEngine::Mode::kOffscreen);
  engine_config.viewport.width = std::max(1, width);
  engine_config.viewport.height = std::max(1, height);

  if (!impl_->desktop_engine.Initialize(engine_config)) {
    return false;
  }

  impl_->renderer = &impl_->desktop_engine.renderer();
  impl_->handler_context.SetRenderer(impl_->renderer);
  impl_->browser_initialized = true;
  impl_->browser_hosted = true;
  return true;
#else
  (void)parent_window;
  (void)width;
  (void)height;
  return false;
#endif
}

void LinuxApp::ResizeBrowserHost(int width, int height) {
  impl_->config.width = std::max(1, width);
  impl_->config.height = std::max(1, height);
  if (impl_->browser_initialized) {
    impl_->desktop_engine.ResizeViewport(impl_->config.width, impl_->config.height);
  }
}

bool LinuxApp::HasNativeBrowser() const {
  return impl_->browser_initialized;
}

bool LinuxApp::FocusBrowser(bool focused) {
  if (!impl_->browser_initialized) {
    return false;
  }
  return impl_->desktop_engine.SendFocusEvent(focused);
}

bool LinuxApp::SendBrowserMouseMove(int x, int y, bool mouse_leave) {
  if (!impl_->browser_initialized) {
    return false;
  }
  return impl_->desktop_engine.SendMouseMoveEvent(x, y, mouse_leave);
}

bool LinuxApp::SendBrowserMouseClick(int x, int y, int button, bool mouse_up, int click_count) {
  if (!impl_->browser_initialized) {
    return false;
  }
  return impl_->desktop_engine.SendMouseClickEvent(x, y, button, mouse_up, click_count);
}

bool LinuxApp::SendBrowserMouseWheel(int x, int y, int delta_x, int delta_y) {
  if (!impl_->browser_initialized) {
    return false;
  }
  return impl_->desktop_engine.SendMouseWheelEvent(x, y, delta_x, delta_y);
}

void LinuxApp::SetFullscreen(bool fullscreen) {
  impl_->desired_fullscreen.store(fullscreen);
}

bool LinuxApp::IsFullscreen() const {
  return impl_->current_fullscreen.load();
}

bool LinuxApp::WantsFullscreen() const {
  return impl_->desired_fullscreen.load();
}

void LinuxApp::ReportFullscreenState(bool fullscreen) {
  impl_->current_fullscreen.store(fullscreen);
  impl_->desired_fullscreen.store(fullscreen);
}

const AppConfig& LinuxApp::config() const {
  return impl_->config;
}

int LinuxApp::port() const {
  return impl_->bound_port;
}

bool LinuxApp::GuiAvailable() const {
  return MOLLOTOV_LINUX_HAS_GTK;
}

bool LinuxApp::MdnsActive() const {
  return impl_->mdns.IsRunning();
}

bool LinuxApp::ScreenshotSupported() const {
  return impl_->browser_initialized;
}

std::string LinuxApp::MdnsStatusText() const {
  return impl_->mdns_status;
}

std::string LinuxApp::RuntimeMode() const {
  return impl_->config.headless ? "headless" : "gui";
}

bool LinuxApp::Navigate(const std::string& url) {
  impl_->renderer->LoadUrl(url);
  impl_->RecordNavigation(url);
  return true;
}

bool LinuxApp::GoBack() {
  if (!impl_->renderer->CanGoBack()) {
    return false;
  }
  impl_->renderer->GoBack();
  impl_->RecordNavigation(impl_->renderer->CurrentUrl());
  return true;
}

bool LinuxApp::GoForward() {
  if (!impl_->renderer->CanGoForward()) {
    return false;
  }
  impl_->renderer->GoForward();
  impl_->RecordNavigation(impl_->renderer->CurrentUrl());
  return true;
}

bool LinuxApp::Reload() {
  impl_->renderer->Reload();
  return true;
}

bool LinuxApp::CanGoBack() const {
  return impl_->renderer->CanGoBack();
}

bool LinuxApp::CanGoForward() const {
  return impl_->renderer->CanGoForward();
}

bool LinuxApp::IsLoading() const {
  return impl_->renderer->IsLoading();
}

std::string LinuxApp::CurrentUrl() const {
  return impl_->renderer->CurrentUrl();
}

std::string LinuxApp::CurrentTitle() const {
  return impl_->renderer->CurrentTitle();
}

std::vector<std::uint8_t> LinuxApp::SnapshotBytes() const {
  return impl_->renderer->TakeSnapshot();
}

std::string LinuxApp::HomeUrl() const {
  return LoadHomeUrl(impl_->config.profile_dir);
}

void LinuxApp::SetHomeUrl(const std::string& url) {
  const std::string normalized = NormalizeHomeUrl(url);
  PersistHomeUrl(impl_->config.profile_dir, normalized);
}

void LinuxApp::AddBookmark(const std::string& title, const std::string& url) {
  impl_->bookmarks.Add(title, url);
  impl_->PersistStores();
}

void LinuxApp::RemoveBookmark(const std::string& id) {
  impl_->bookmarks.Remove(id);
  impl_->PersistStores();
}

void LinuxApp::ClearBookmarks() {
  impl_->bookmarks.RemoveAll();
  impl_->PersistStores();
}

void LinuxApp::ClearHistory() {
  impl_->history.Clear();
  impl_->PersistStores();
}

std::string LinuxApp::BookmarksJson() const {
  return impl_->bookmarks.ToJson();
}

std::string LinuxApp::HistoryJson() const {
  return impl_->history.ToJson();
}

void LinuxApp::ShowToast(const std::string& message) {
  std::lock_guard<std::mutex> lock(impl_->toast_mutex);
  impl_->pending_toast = message;
  if (impl_->config.headless && !message.empty()) {
    std::cout << "[toast] " << message << '\n';
  }
}

std::string LinuxApp::ConsumeToast() {
  std::lock_guard<std::mutex> lock(impl_->toast_mutex);
  std::string message = std::move(impl_->pending_toast);
  impl_->pending_toast.clear();
  return message;
}

}  // namespace mollotov::linuxapp
