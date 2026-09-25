#include "linux_app_internal.h"
namespace kelpie::linuxapp {
bool LinuxApp::FinishShutdown(){ return true; }
std::vector<TabSnapshot> LinuxApp::Tabs() const { return {}; }
void LinuxApp::NewTab(bool) {}
bool LinuxApp::IsolateNewTabs() const { return false; }
void LinuxApp::SetIsolateNewTabs(bool) {}
void LinuxApp::ActivateTab(const std::string&) {}
void LinuxApp::CloseTab(const std::string&) {}
void LinuxApp::CycleTab(int) {}
OffscreenFrame LinuxApp::ViewFrame() const { return {}; }
void LinuxApp::InputModifiers(unsigned) {}
bool LinuxApp::Key(int,int,unsigned,bool) { return false; }
bool LinuxApp::CommitText(const std::string&,bool) { return false; }
account::AccountState LinuxApp::AccountState() const { return {}; }
void LinuxApp::AccountSignIn() { ShowToast("Accounts require the Chromium build"); }
void LinuxApp::AccountSignOut() {}
void LinuxApp::AccountRefresh() {}
std::pair<int,int> LinuxApp::TakeResizeRequest() { return {}; }
}
