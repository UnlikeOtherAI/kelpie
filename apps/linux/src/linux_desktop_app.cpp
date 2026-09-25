#include "linux_desktop_internal.h"
#include "gui_shell.h"
#include "headless_shell.h"
#include "kelpie/response_helpers.h"
#include <fstream>
#include <iostream>
#include <thread>

namespace kelpie::linuxapp {
std::string ReadProfile(const std::filesystem::path& path) {
  std::ifstream input(path); return {std::istreambuf_iterator<char>(input),{}};
}
LinuxApp::Impl::Impl(AppConfig settings,int count,char** args)
    :config(std::move(settings)),argc(count),argv(args),device(config.profile_dir),
     account(desktop.bookmark_store()) {
  profile.Open(config.profile_dir,config.readiness_path);
  const std::filesystem::path root(config.profile_dir);
  desktop.bookmark_store().LoadJson(ReadProfile(root/"bookmarks.json"));
  desktop.history_store().LoadJson(ReadProfile(root/"history.json"));
  home=ReadProfile(root/"home_url.txt");
  while(!home.empty() && (home.back()=='\n'||home.back()=='\r')) home.pop_back();
  if(home.empty()) home="kelpie://start";
}
LinuxApp::LinuxApp(AppConfig config,int argc,char* argv[])
    :impl_(std::make_unique<Impl>(std::move(config),argc,argv)) {}
LinuxApp::~LinuxApp() {
  RequestShutdown();
  while(!FinishShutdown()) { PumpBrowser(); std::this_thread::sleep_for(std::chrono::milliseconds(5)); }
}
int LinuxApp::Run() {
  if(impl_->config.headless) {
    if(!AttachBrowserHost(0,impl_->config.width,impl_->config.height)) return 1;
    return HeadlessShell(*this).Run();
  }
  if(!GuiAvailable()) { std::cerr<<"GTK support is unavailable\n"; return 1; }
  return GUIShell(*this).Run();
}
bool LinuxApp::AttachBrowserHost(std::uintptr_t,int width,int height) {
  if(impl_->started) { ResizeBrowserHost(width,height); return true; }
  DesktopApp::Config runtime;
  runtime.platform=Platform::kLinux; runtime.app_name="kelpie"; runtime.app_version=KELPIE_LINUX_VERSION;
  runtime.port=impl_->config.port; runtime.bind_host="127.0.0.1";
  runtime.control_token=impl_->profile.token(); runtime.device_id=impl_->device.Collect().id;
  runtime.start_stdio_mcp=impl_->config.mcp_stdio; runtime.device_info_provider=impl_.get();
  runtime.bookmark_action=[this](const std::string& action,const json& params) { return impl_->account.BookmarkAction(action,params); };
  runtime.bookmarks_supplier=[this] { return impl_->account.Bookmarks(); };
  runtime.request_shutdown=[this] { RequestShutdown(); return BrowserControlResult::Success(); };
  runtime.set_home=[this](std::string url) { SetHomeUrl(url); return BrowserControlResult::Success(); };
  runtime.get_home=[this](std::string* url) { *url=HomeUrl(); return BrowserControlResult::Success(); };
  runtime.show_native_toast=[this](std::string message) { ShowToast(message); return BrowserControlResult::Success(); };
  runtime.set_native_fullscreen=[this](bool value) { SetFullscreen(value); return BrowserControlResult::Success(); };
  runtime.get_native_fullscreen=[this](bool* value) { *value=IsFullscreen(); return BrowserControlResult::Success(); };
  runtime.viewport_supplier=[this] { auto view=impl_->desktop.engine().viewport(); return json{{"width",view.width},{"height",view.height},{"devicePixelRatio",1.0},{"platform","linux"}}; };
  runtime.resize_viewport=[this](int w,int h) { impl_->requested_width=w; impl_->requested_height=h; return true; };
  runtime.reset_viewport=[this] { impl_->requested_width=impl_->config.width; impl_->requested_height=impl_->config.height; return true; };
  auto& engine=runtime.engine;
  engine.mode=DesktopEngine::Mode::kOffscreen; engine.argc=impl_->argc; engine.argv=impl_->argv;
  engine.viewport={std::max(1,width),std::max(1,height)};
  engine.initial_url=impl_->config.url;
  const auto executable=std::filesystem::read_symlink("/proc/self/exe");
  engine.browser_subprocess_path=executable.string(); engine.resources_dir_path=executable.parent_path().string();
  engine.locales_dir_path=(executable.parent_path()/"locales").string();
  engine.cache_path=impl_->config.profile_dir+"/cef-cache";
  engine.root_cache_path=engine.cache_path; engine.partitions_path=engine.cache_path;
  if(engine.initial_url.empty()) impl_->LoadSession(engine);
  if(!impl_->desktop.Start(runtime)) { ShowToast(impl_->desktop.last_error()); return false; }
  impl_->started=true;
  impl_->profile.Publish(runtime.device_id,impl_->desktop.http_server().port(),runtime.start_stdio_mcp);
  return true;
}
void LinuxApp::RequestShutdown() { impl_->closing=true; }
bool LinuxApp::FinishShutdown() {
  if(!impl_->closing) return false;
  impl_->account.Shutdown(); impl_->desktop.BeginShutdown();
  if(!impl_->account.Drain() || !impl_->desktop.IsShutdownReady()) return false;
  if(impl_->started) impl_->Save();
  if(!impl_->desktop.Stop()) return false;
  impl_->profile.Clear(); impl_->started=false; impl_->running=false; return true;
}
bool LinuxApp::IsRunning() const { return impl_->running && !impl_->closing; }
void LinuxApp::PumpBrowser() {
  impl_->desktop.Tick(); impl_->account.Poll();
  if(impl_->started && !impl_->closing && std::chrono::steady_clock::now()-impl_->last_save>std::chrono::seconds(1)) {
    impl_->Save(); impl_->last_save=std::chrono::steady_clock::now();
  }
}
void LinuxApp::Impl::LoadSession(DesktopEngine::Config& engine) {
  auto saved=json::parse(ReadProfile(std::filesystem::path(config.profile_dir)/"session.json"),nullptr,false);
  if(saved.is_object() && saved.contains("tabs") && saved["tabs"].is_array()) {
    engine.restored_next_tab_id=saved.value("nextTabId",std::uint64_t{1});
    for(const auto& tab:saved["tabs"]) {
      if(!tab.is_object() || !tab.contains("id") || !tab.contains("url")) continue;
      DesktopEngine::RestoredTab value{tab.value("id",""),tab.value("url",""),tab.value("active",false)};
      if(tab.contains("partition")&&tab["partition"].is_string()) value.partition=tab["partition"].get<std::string>();
      if(tab.contains("name")&&tab["name"].is_string()) value.name=tab["name"].get<std::string>();
      if(!value.id.empty()) engine.restored_tabs.push_back(std::move(value));
    }
  }
  if(engine.restored_tabs.empty()) engine.initial_url=ReadProfile(std::filesystem::path(config.profile_dir)/"session_url.txt");
}
void LinuxApp::Impl::Save() {
  const std::filesystem::path root(config.profile_dir);
  auto write_changed=[&](const char* file,std::string data,std::string& previous) {
    if(data!=previous) { AtomicWrite(root/file,data); previous=std::move(data); }
  };
  write_changed("bookmarks.json",desktop.bookmark_store().ToJson(),last_bookmarks);
  write_changed("history.json",desktop.history_store().ToJson(),last_history);
  DesktopEngine::SessionState session;
  if(!desktop.engine().GetSessionState(&session,std::chrono::milliseconds(100)).ok) return;
  json data{{"nextTabId",session.next_tab_id},{"tabs",json::array()}};
  for(const auto& tab:session.tabs) {
    if(!tab.persistent) continue;
    json item{{"id",tab.id},{"url",tab.url},{"active",tab.active}};
    if(tab.name) item["name"]=*tab.name;
    if(tab.partition) item["partition"]=*tab.partition;
    data["tabs"].push_back(item);
  }
  write_changed("session.json",data.dump(),last_session);
}
const AppConfig& LinuxApp::config() const { return impl_->config; }
int LinuxApp::port() const { return impl_->desktop.http_server().port(); }
bool LinuxApp::GuiAvailable() const { return KELPIE_LINUX_HAS_GTK; }
bool LinuxApp::MdnsActive() const { return false; }
std::string LinuxApp::MdnsStatusText() const { return "Local agent control"; }
std::string LinuxApp::RuntimeMode() const { return impl_->config.headless?"headless":"gui"; }
bool LinuxApp::HasNativeBrowser() const { return impl_->started; }
bool LinuxApp::ScreenshotSupported() const { return impl_->started; }
void LinuxApp::ResizeBrowserHost(int w,int h) { if(impl_->started) impl_->desktop.engine().ResizeViewport(w,h); }
bool LinuxApp::FocusBrowser(bool value) { return impl_->desktop.engine().SendFocusEvent(value); }
bool LinuxApp::SendBrowserMouseMove(int x,int y,bool leave) { return impl_->desktop.engine().SendMouseMoveEvent(x,y,leave); }
bool LinuxApp::SendBrowserMouseClick(int x,int y,int button,bool up,int count) { return impl_->desktop.engine().SendMouseClickEvent(x,y,button,up,count); }
bool LinuxApp::SendBrowserMouseWheel(int x,int y,int dx,int dy) { return impl_->desktop.engine().SendMouseWheelEvent(x,y,dx,dy); }
void LinuxApp::InputModifiers(unsigned value) { impl_->desktop.engine().SetInputModifiers(value); }
bool LinuxApp::Key(int key,int native,unsigned modifiers,bool up) { return impl_->desktop.engine().SendKeyEvent(key,native,modifiers,up); }
bool LinuxApp::CommitText(const std::string& text) { return impl_->desktop.engine().CommitText(text); }
OffscreenFrame LinuxApp::ViewFrame() const { return impl_->desktop.engine().ViewFrame(); }
std::vector<std::uint8_t> LinuxApp::SnapshotBytes() const { return ViewFrame().pixels; }
void LinuxApp::SetFullscreen(bool value) { impl_->desired_fullscreen=value; }
bool LinuxApp::IsFullscreen() const { return impl_->fullscreen; }
bool LinuxApp::WantsFullscreen() const { return impl_->desired_fullscreen; }
void LinuxApp::ReportFullscreenState(bool value) { impl_->fullscreen=value; impl_->desired_fullscreen=value; }
std::pair<int,int> LinuxApp::TakeResizeRequest() { return {impl_->requested_width.exchange(0),impl_->requested_height.exchange(0)}; }
}  // namespace kelpie::linuxapp
