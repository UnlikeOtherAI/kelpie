#include "connect_executor.h"
#include "websocket_codec.h"
#include "connect_text.h"
#include "encrypted_blob_store.h"
#include "account_protocol.h"
#include <cassert>
#include <fstream>
#include <ctime>
using namespace kelpie;
using namespace kelpie::connect;
namespace {
class Browser final:public DesktopBrowserControl {
 public:
  TabSnapshot tab{"owned",7,"https://example.org","Page",false};
  TabLease used; int effects=0; bool race=false;
  Browser() { tab.document_version="document-1"; }
  BrowserControlResult Check(TabLease lease) {
    used=lease;
    if(lease.id!=tab.id || lease.generation!=tab.generation || !lease.document_version || *lease.document_version!=tab.document_version ||
        (lease.require_active && !tab.active) || (lease.cancelled && lease.cancelled->load()) || (lease.deadline && std::chrono::steady_clock::now()>=*lease.deadline))return BrowserControlResult::Failure("STALE","Stale");
    return BrowserControlResult::Success(tab);
  }
  BrowserControlResult GetTabs(std::vector<TabSnapshot>* result,Timeout)override { *result={tab};return BrowserControlResult::Success(); }
  BrowserControlResult ResolveTab(const std::optional<std::string>& id,const std::optional<std::uint64_t>&,TabLease* lease,Timeout)override {
    if(!id || *id!=tab.id)return BrowserControlResult::Failure("MISSING","Missing");
    *lease={tab.id,tab.generation};return BrowserControlResult::Success(tab);
  }
  BrowserControlResult ActivateTab(TabLease lease,Timeout)override { const auto result=Check(lease); if(result.ok) { tab.active=true;if(race)tab.document_version="document-2"; }return result; }
  BrowserControlResult CreateTab(const NewTabRequest& request,TabSnapshot* out,Timeout)override {
    if(request.cancelled && request.cancelled->load())return BrowserControlResult::Failure("CANCELLED","Cancelled");
    ++effects;tab.url=request.url;*out=tab;return BrowserControlResult::Success(tab);
  }
  BrowserControlResult CloseTab(TabLease,Timeout)override { return BrowserControlResult::Failure("UNSUPPORTED","Forbidden"); }
  BrowserControlResult Navigate(std::optional<TabLease> lease,std::string,TabSnapshot* out,Timeout)override { const auto r=Check(*lease);if(r.ok) { ++effects;*out=tab; }return r; }
  BrowserControlResult Back(TabLease lease,TabSnapshot* out,Timeout timeout)override { return Navigate(lease,"",out,timeout); }
  BrowserControlResult Forward(TabLease lease,TabSnapshot* out,Timeout timeout)override { return Navigate(lease,"",out,timeout); }
  BrowserControlResult Reload(TabLease lease,TabSnapshot* out,Timeout timeout)override { return Navigate(lease,"",out,timeout); }
  BrowserControlResult Evaluate(TabLease lease,std::string,Json* out,Timeout timeout)override { assert(timeout<=std::chrono::seconds(10));const auto r=Check(lease);if(r.ok)*out={{"text","Page content"}};return r; }
  BrowserControlResult Screenshot(TabLease lease,BrowserScreenshot* out,Timeout)override { const auto r=Check(lease);out->base64_data="AA==";return r; }
  BrowserControlResult DispatchTrustedInput(TabLease lease,const Json&,Json* out,Timeout)override { const auto r=Check(lease);if(r.ok){++effects;*out={{"success",true}};}return r; }
  BrowserControlResult DevTools(TabLease lease,std::string,const Json&,Json* out,Timeout)override { const auto r=Check(lease);if(r.ok)*out={{"nodes",Json::array()}};return r; }
  BrowserControlResult GetCookies(TabLease,const Json&,Json*,Timeout)override { std::abort(); }
  BrowserControlResult SetCookies(TabLease,const Json&,Json*,Timeout)override { std::abort(); }
  BrowserControlResult DeleteCookies(TabLease,const Json&,Json*,Timeout)override { std::abort(); }
  BrowserControlResult GetDialog(TabLease,Json*,Timeout)override { std::abort(); }
  BrowserControlResult HandleDialog(TabLease,const Json&,Json*,Timeout)override { std::abort(); }
};
Json Command(std::string operation,Json input=Json::object()) {
  return {{"operation",operation},{"input",input},{"deadline","2099-10-11T12:00:00.000Z"},{"tabId","owned"},{"tabVersion","document-1"}};
}
}
int main() {
  assert(Utf8Prefix(std::string(119,'a')+"\xc3\xa9",120)==std::string(119,'a'));
  assert(Utf8Prefix(std::string(118,'a')+"\xf0\x9f\x98\x80",120)==std::string(118,'a'));
  assert(Utf8Prefix("\xc3\xa9\xf0\x9f\x98\x80",6)=="\xc3\xa9\xf0\x9f\x98\x80");
  assert((!Json{{"label",Utf8Prefix(std::string(119,'a')+"\xc3\xa9",120)}}.dump().empty()));
  Browser browser;Executor executor(browser);auto guard=std::make_shared<std::atomic<bool>>(false);
  assert(executor.Execute(Command("click",{{"selector","#go"}}),guard)["state"]=="completed");
  assert(browser.effects==1 && browser.tab.active && browser.used.cancelled==guard && browser.used.document_version=="document-1");
  browser.race=true;
  assert(executor.Execute(Command("type",{{"selector","#field"},{"text","value"}}),guard)["state"]=="failed");
  assert(browser.effects==1);browser.race=false;
  assert(executor.Execute(Command("reload"),guard)["state"]=="failed"); // Same URL, replaced document.
  browser.tab.document_version="document-1";guard->store(true);
  assert(executor.Execute(Command("click",{{"selector","#go"}}),guard)["state"]=="cancelled");
  guard->store(false);auto expired=Command("click",{{"selector","#go"}});expired["deadline"]="2000-01-01T00:00:00.000Z";
  assert(executor.Execute(expired,guard)["error"]=="DEADLINE_EXCEEDED");assert(browser.effects==1);
  for(auto url:{"file:///private","javascript:alert(1)","https://user:password@example.org","https://authentication.unlikeotherai.com/oauth/me"})
    assert(executor.Execute(Command("open",{{"url",url}}),guard)["error"]=="INVALID_URL");
  assert(executor.Execute(Command("extract",{{"question","Read page"}}),guard)["error"]=="MODEL_NOT_READY");
  assert(executor.Execute(Command("snapshot"),guard)["output"]["page"]["text"]=="Page content");
  assert(!executor.Execute(Command("snapshot"),guard)["output"].contains("image"));
  Executor local(browser,[](const Json& request) { assert(!request.contains("context") && request["agent"]==false);return Json{{"success",true},{"response",std::string(100,'a')}}; });
  assert(local.Execute(Command("extract",{{"question","Read page"},{"maxOutputCharacters",64}}),guard)["output"]["summary"].get<std::string>().size()==64);
  const auto extracted=local.Execute(Command("extract",{{"question","Read page"}}),guard)["output"];
  assert(extracted["tabId"]=="owned" && extracted["tabVersion"]=="document-1" && extracted["evidence"][0]["url"]=="https://example.org" && extracted["evidence"][0]["excerpt"]=="Page content" && extracted["evidence"][0].contains("observedAt"));
  Executor cancel_infer(browser,[&](const Json&) { guard->store(true);return Json{{"success",true},{"response","stale"}}; });
  assert(cancel_infer.Execute(Command("extract",{{"question","Read page"}}),guard)["state"]=="cancelled");guard->store(false);
  Executor changed_infer(browser,[&](const Json&) { browser.tab.document_version="changed";return Json{{"success",true},{"response","stale"}}; });
  assert(changed_infer.Execute(Command("extract",{{"question","Read page"}}),guard)["error"]=="PAGE_CHANGED");browser.tab.document_version="document-1";
  Executor focus_infer(browser,[&](const Json&) { browser.tab.active=false;return Json{{"success",true},{"response","stale"}}; });
  assert(focus_infer.Execute(Command("extract",{{"question","Read page"}}),guard)["error"]=="PAGE_CHANGED");
  const auto future_time=std::time(nullptr)+300;std::tm future{};
#ifdef _WIN32
  gmtime_s(&future,&future_time);
#else
  gmtime_r(&future_time,&future);
#endif
  char future_text[32]{};std::strftime(future_text,sizeof(future_text),"%Y-%m-%dT%H:%M:%S.000Z",&future);
  auto long_job=Command("extract",{{"question","Read page"}});long_job["deadline"]=future_text;
  std::optional<std::chrono::steady_clock::time_point> inference_deadline;
  Executor long_inference(browser,[&](const Json&) { inference_deadline=browser.used.deadline;return Json{{"success",true},{"response","Answer"}}; });
  assert(long_inference.Execute(long_job,guard)["state"]=="completed");
  assert(inference_deadline==browser.used.deadline && inference_deadline && *inference_deadline-std::chrono::steady_clock::now()>std::chrono::minutes(4));
  std::string split="\x81\x05hello";auto half=split.substr(0,4);assert(!DecodeFrame(half));half+=split.substr(4);assert(DecodeFrame(half)->payload=="hello");
  std::string masked="\x81\x80";bool rejected=false;try { DecodeFrame(masked); }catch(...) { rejected=true; }assert(rejected);
  const auto profile=std::filesystem::temp_directory_path()/account::RandomAccountValue();
  auto first=account::MakeEncryptedBlobStore(profile,"journal",1024),second=account::MakeEncryptedBlobStore(profile,"controls",1024);
  assert(first->Save("private page output") && second->Save("controls"));assert(first->Load()=="private page output");first->Clear();assert(second->Load()=="controls");
  assert(!second->Save(std::string(1025,'x')));
  std::filesystem::remove_all(profile);
}
