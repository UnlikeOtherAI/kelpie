#include "linux_desktop_internal.h"
#include "account_protocol.h"
#include "kelpie/response_helpers.h"
#include <algorithm>
#include <thread>
#include <utility>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>
extern char** environ;

namespace kelpie::linuxapp {
namespace {
std::optional<TabLease> Active(LinuxApp& app) {
  for(const auto& tab:app.Tabs()) if(tab.active) return TabLease{tab.id,tab.generation};
  return std::nullopt;
}
bool OpenExternal(const std::string& url) {
  // Pick a separate browser executable even if Kelpie owns the desktop URL association.
  for(const char* browser:{"firefox","google-chrome","chromium","chromium-browser"}) {
    pid_t child;
    char* args[]={const_cast<char*>(browser),const_cast<char*>(url.c_str()),nullptr};
    if(posix_spawnp(&child,browser,nullptr,nullptr,args,environ)==0) {
      std::thread([child] { int status; while(waitpid(child,&status,0)<0 && errno==EINTR) {} }).detach();
      return true;
    }
  }
  return false;
}
}
std::vector<TabSnapshot> LinuxApp::Tabs() const {
  std::vector<TabSnapshot> tabs;
  if(impl_->started) impl_->desktop.engine().GetTabs(&tabs,std::chrono::milliseconds(50));
  return tabs;
}
void LinuxApp::NewTab(bool isolated) {
  NewTabRequest request;
  if(isolated || impl_->isolate_new_tabs) request.partition="isolated-"+account::RandomAccountValue();
  TabSnapshot tab;
  auto result=impl_->desktop.engine().CreateTab(request,&tab,std::chrono::seconds(3));
  if(result.ok) ActivateTab(tab.id); else ShowToast(result.message);
}
bool LinuxApp::IsolateNewTabs() const { return impl_->isolate_new_tabs; }
void LinuxApp::SetIsolateNewTabs(bool enabled) {
  try {
    AtomicWrite(std::filesystem::path(impl_->config.profile_dir)/"isolate_new_tabs.txt",enabled?"true":"false");
    impl_->isolate_new_tabs=enabled;
  } catch(const std::exception& error) { ShowToast(error.what()); }
}
void LinuxApp::ActivateTab(const std::string& id) {
  for(const auto& tab:Tabs()) if(tab.id==id) {
    impl_->desktop.engine().ActivateTab({tab.id,tab.generation},std::chrono::seconds(1)); return;
  }
}
void LinuxApp::CloseTab(const std::string& id) {
  for(const auto& tab:Tabs()) if(tab.id==id) {
    impl_->desktop.engine().CloseTab({tab.id,tab.generation},std::chrono::seconds(1)); return;
  }
}
void LinuxApp::CycleTab(int direction) {
  auto tabs=Tabs(); if(tabs.empty()) return;
  for(std::size_t i=0;i<tabs.size();++i) if(tabs[i].active) {
    ActivateTab(tabs[(i+tabs.size()+direction)%tabs.size()].id); return;
  }
}
bool LinuxApp::Navigate(const std::string& url) {
  std::string resolved=url;
  if(resolved.find(':')==std::string::npos) resolved="https://"+resolved;
  auto result=impl_->desktop.engine().Navigate(Active(*this),resolved,nullptr,std::chrono::seconds(3));
  if(!result.ok) ShowToast(result.message); return result.ok;
}
bool LinuxApp::GoBack() { auto tab=Active(*this); return tab && impl_->desktop.engine().Back(*tab,nullptr,std::chrono::seconds(1)).ok; }
bool LinuxApp::GoForward() { auto tab=Active(*this); return tab && impl_->desktop.engine().Forward(*tab,nullptr,std::chrono::seconds(1)).ok; }
bool LinuxApp::Reload() { auto tab=Active(*this); return tab && impl_->desktop.engine().Reload(*tab,nullptr,std::chrono::seconds(1)).ok; }
bool LinuxApp::CanGoBack() const { for(auto& t:Tabs()) if(t.active) return t.can_go_back; return false; }
bool LinuxApp::CanGoForward() const { for(auto& t:Tabs()) if(t.active) return t.can_go_forward; return false; }
bool LinuxApp::IsLoading() const { for(auto& t:Tabs()) if(t.active) return t.is_loading; return false; }
std::string LinuxApp::CurrentUrl() const { for(auto& t:Tabs()) if(t.active) return t.url; return {}; }
std::string LinuxApp::CurrentTitle() const { for(auto& t:Tabs()) if(t.active) return t.title; return {}; }
std::string LinuxApp::HomeUrl() const { std::lock_guard lock(impl_->state_mutex); return impl_->home; }
void LinuxApp::SetHomeUrl(const std::string& url) {
  std::lock_guard lock(impl_->state_mutex); impl_->home=url.empty()?"kelpie://start":url;
  AtomicWrite(std::filesystem::path(impl_->config.profile_dir)/"home_url.txt",impl_->home);
}
void LinuxApp::AddBookmark(const std::string& title,const std::string& url) {
  if(url.starts_with("kelpie:")||url=="about:blank") return;
  if(!impl_->account.StartBookmarkAction("add",{{"url",url},{"title",title}})) ShowToast("Favorites are syncing; try again shortly");
}
void LinuxApp::RemoveBookmark(const std::string& id) { impl_->account.StartBookmarkAction("remove",{{"id",id}}); }
void LinuxApp::ClearBookmarks() { impl_->account.StartBookmarkAction("clear"); }
void LinuxApp::ClearHistory() { impl_->desktop.history_store().Clear(); impl_->Save(); }
std::string LinuxApp::BookmarksJson() const { return impl_->account.Bookmarks(); }
std::string LinuxApp::HistoryJson() const { return impl_->desktop.history_store().ToJson(); }
account::AccountState LinuxApp::AccountState() const { return impl_->account.State(); }
void LinuxApp::AccountSignIn() { impl_->account.StartSignIn(impl_->config.profile_dir,OpenExternal); }
void LinuxApp::AccountSignOut() { impl_->account.SignOut(); }
void LinuxApp::AccountRefresh() { impl_->account.StartBookmarkAction("refresh"); }
void LinuxApp::ShowToast(const std::string& message) { std::lock_guard lock(impl_->state_mutex); impl_->toast=message; }
std::string LinuxApp::ConsumeToast() { std::lock_guard lock(impl_->state_mutex); return std::exchange(impl_->toast,{}); }
LinuxApp::json LinuxApp::Impl::GetDeviceInfo() const {
  auto snapshot=device.Collect(); snapshot.ip="127.0.0.1";
  auto data=device.ToJson(snapshot,desktop.http_server().bound_port(),view_width,view_height,false,started,"",KELPIE_LINUX_VERSION,0);
  data["controlMode"]="loopback"; data["success"]=true; return data;
}
LinuxApp::json LinuxApp::DeviceInfo() const { return impl_->GetDeviceInfo(); }
LinuxApp::json LinuxApp::Capabilities() const { return impl_->desktop.router().Dispatch("get-capabilities",{}).body; }
LinuxApp::json LinuxApp::ReportIssue(const json& params) { int status; return HandleApiRequest("report-issue",params,&status); }
LinuxApp::json LinuxApp::HandleApiRequest(std::string_view endpoint,const json& params,int* status) {
  auto response=impl_->desktop.router().Dispatch(endpoint,params); if(status)*status=response.status_code; return response.body;
}
LinuxApp::json LinuxApp::ConsoleMessages(const std::optional<std::string>& level) const {
  json params=json::object(); if(level) params["level"]=*level;
  return impl_->desktop.router().Dispatch("get-console-messages",params).body;
}
LinuxApp::json LinuxApp::NetworkEntries(const std::optional<std::string>& method,const std::optional<std::string>& type,const std::optional<std::string>& source) const {
  json params=json::object(); if(method)params["method"]=*method; if(type)params["type"]=*type; if(source)params["source"]=*source;
  return impl_->desktop.router().Dispatch("get-network-log",params).body;
}
}  // namespace kelpie::linuxapp
