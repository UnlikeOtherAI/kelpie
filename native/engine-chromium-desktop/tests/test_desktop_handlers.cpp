#include "kelpie/cef_renderer.h"

#include <cassert>
#include <cstdlib>
#undef assert
#define assert(expression) do { if (!(expression)) std::abort(); } while (false)

#include "kelpie/desktop_router.h"
#include "kelpie/handler_context.h"
#include "handlers/bookmark_handler.h"
#include "handlers/browser_mgmt_handler.h"
#include "handlers/cookie_handler.h"
#include "handlers/console_handler.h"
#include "handlers/device_handler.h"
#include "handlers/dialog_handler.h"
#include "handlers/navigation_handler.h"
#include "handlers/dom_handler.h"
#include "handlers/evaluate_handler.h"
#include "handlers/history_handler.h"
#include "handlers/inspection_handler.h"
#include "handlers/interaction_handler.h"
#include "handlers/network_handler.h"
#include "handlers/partition_handler.h"
#include "handlers/renderer_handler.h"
#include "handlers/shell_handler.h"
#include "handlers/viewport_handler.h"

namespace {
class StubDeviceInfoProvider final : public kelpie::DeviceInfoProvider {
 public:
  nlohmann::json GetDeviceInfo() const override { return {{"name", "Stub Desktop"}}; }
  kelpie::StringMap GetMdnsMetadata() const override { return {{"name", "Stub Desktop"}}; }
};

class MockControl final : public kelpie::DesktopBrowserControl {
 public:
  kelpie::TabLease last_lease; nlohmann::json last_cookie; std::string last_devtools_method; nlohmann::json last_devtools_params; bool stale = false; bool timeout_eval = false; std::uint64_t nav_requested = 1; std::uint64_t nav_completed = 1; std::string nav_error; int nav_polls = 0;
  kelpie::TabSnapshot first{"first", 3, "https://one.test", "One", true};
  kelpie::TabSnapshot second{"second", 9, "https://two.test", "Two", false};
  kelpie::BrowserControlResult GetTabs(std::vector<kelpie::TabSnapshot>* tabs, Timeout) override { *tabs={first,second}; return kelpie::BrowserControlResult::Success(); }
  kelpie::BrowserControlResult GetNavigationState(kelpie::TabLease lease, kelpie::BrowserNavigationState* state, Timeout) override {
    ++nav_polls;
    if (nav_error.empty() && nav_completed == 0 && nav_polls >= 2) nav_completed = nav_requested;
    *state = {lease.id == "second" ? second : first, nav_requested, nav_completed, nav_error};
    return kelpie::BrowserControlResult::Success(state->tab);
  }
  kelpie::BrowserControlResult ResolveTab(const std::optional<std::string>& id, const std::optional<std::uint64_t>& gen, kelpie::TabLease* lease, Timeout) override {
    if (stale || (gen && ((id && *id == "second" && *gen != 9) || (!id && *gen != 3)))) return kelpie::BrowserControlResult::Failure("TAB_STALE", "tab lease is stale");
    const auto& tab = id && *id == "second" ? second : first; *lease={tab.id,tab.generation}; last_lease=*lease; return kelpie::BrowserControlResult::Success(tab);
  }
  kelpie::NewTabRequest last_new_tab; std::string last_deleted_partition; bool partition_deleting=false; bool partitions_supported=true;
  kelpie::BrowserControlResult CreateTab(const kelpie::NewTabRequest& request, kelpie::TabSnapshot* tab, Timeout) override {
    last_new_tab=request;
    if (partition_deleting && request.partition) return kelpie::BrowserControlResult::Failure("PARTITION_DELETING", "partition is being deleted");
    kelpie::TabSnapshot created=second; created.name=request.name; created.partition=request.partition;
    if (request.partition) created.persistent=request.persistent;
    *tab=created; return kelpie::BrowserControlResult::Success(created);
  }
  kelpie::BrowserControlResult GetPartitions(std::vector<kelpie::PartitionInfo>* out, Timeout) override {
    if (!partitions_supported) return kelpie::DesktopBrowserControl::GetPartitions(out, Timeout::zero());
    *out={{"work",2,true},{"scratch",1,false}}; return kelpie::BrowserControlResult::Success();
  }
  kelpie::BrowserControlResult DeletePartition(const std::string& id, kelpie::PartitionDeletion* out, Timeout) override {
    last_deleted_partition=id;
    *out={id=="work", id=="work" ? std::size_t{2} : std::size_t{0}};
    return kelpie::BrowserControlResult::Success();
  }
  kelpie::BrowserControlResult ActivateTab(kelpie::TabLease lease, Timeout) override { last_lease=lease; return kelpie::BrowserControlResult::Success(second); }
  kelpie::BrowserControlResult CloseTab(kelpie::TabLease lease, Timeout) override { last_lease=lease; return kelpie::BrowserControlResult::Success(second); }
  kelpie::BrowserControlResult Navigate(std::optional<kelpie::TabLease> lease, std::string, kelpie::TabSnapshot* tab, Timeout) override { last_lease=*lease; *tab=first; return kelpie::BrowserControlResult::Success(first); }
  kelpie::BrowserControlResult Back(kelpie::TabLease lease, kelpie::TabSnapshot* tab, Timeout) override { last_lease=lease; *tab=first; return kelpie::BrowserControlResult::Success(first); }
  kelpie::BrowserControlResult Forward(kelpie::TabLease lease, kelpie::TabSnapshot* tab, Timeout) override { last_lease=lease; *tab=first; return kelpie::BrowserControlResult::Success(first); }
  kelpie::BrowserControlResult Reload(kelpie::TabLease lease, kelpie::TabSnapshot* tab, Timeout) override { last_lease=lease; *tab=first; return kelpie::BrowserControlResult::Success(first); }
  kelpie::BrowserControlResult Evaluate(kelpie::TabLease lease, std::string script, Json* value, Timeout) override { last_lease=lease; if(timeout_eval) return kelpie::BrowserControlResult::Failure("TIMEOUT","evaluation timed out"); if(script.find("readyState")!=std::string::npos) *value="complete"; else if(script.find("attached")!=std::string::npos) *value={{"attached",true},{"visible",true},{"text","matched"}}; else if(script.find("found")!=std::string::npos) *value={{"found",true},{"text","matched"}}; else *value={{"elements",nlohmann::json::array()},{"count",0}}; return kelpie::BrowserControlResult::Success(lease.id=="second"?second:first); }
  kelpie::BrowserControlResult Screenshot(kelpie::TabLease lease, kelpie::BrowserScreenshot* image, Timeout) override { last_lease=lease; image->base64_data="AA=="; return kelpie::BrowserControlResult::Success(second); }
  kelpie::BrowserControlResult GetCookies(kelpie::TabLease lease, const Json&, Json* out, Timeout) override { last_lease=lease; *out=nlohmann::json::array({{{"name","a"},{"value","b"}}}); return kelpie::BrowserControlResult::Success(second); }
  kelpie::BrowserControlResult SetCookies(kelpie::TabLease lease, const Json& cookies, Json* out, Timeout) override { last_lease=lease; last_cookie=cookies; *out={{"set",true}}; return kelpie::BrowserControlResult::Success(second); }
  kelpie::BrowserControlResult DeleteCookies(kelpie::TabLease lease, const Json&, Json* out, Timeout) override { last_lease=lease; *out={{"deleted",1}}; return kelpie::BrowserControlResult::Success(second); }
  kelpie::BrowserControlResult DispatchTrustedInput(kelpie::TabLease lease, const Json&, Json* out, Timeout) override { last_lease=lease; *out={{"trusted",true}}; return kelpie::BrowserControlResult::Success(second); }
  kelpie::BrowserControlResult GetDialog(kelpie::TabLease lease, Json* out, Timeout) override { last_lease=lease; *out={{"showing",true},{"dialog",{{"type","alert"},{"message","hi"},{"defaultValue",nullptr}}}}; return kelpie::BrowserControlResult::Success(second); }
  kelpie::BrowserControlResult HandleDialog(kelpie::TabLease lease, const Json&, Json* out, Timeout) override { last_lease=lease; *out={{"action","accept"},{"dialogType","confirm"}}; return kelpie::BrowserControlResult::Success(second); }
  kelpie::BrowserControlResult DevTools(kelpie::TabLease lease, std::string method, const Json& params, Json* out, Timeout) override {
    last_lease=lease; last_devtools_method=std::move(method); last_devtools_params=params;
    *out={{"nodes", nlohmann::json::array({{{"nodeId","root"}, {"role", {{"value","button"}}}}})}};
    return kelpie::BrowserControlResult::Success(second);
  }
};
}  // namespace

int main() {
  kelpie::CefRenderer renderer; kelpie::HandlerContext context(&renderer); kelpie::BookmarkStore bookmarks; kelpie::HistoryStore history; kelpie::ConsoleStore console; kelpie::NetworkTrafficStore network; StubDeviceInfoProvider device_info; MockControl control;
  int width=1280,height=720;
  kelpie::DesktopHandlerRuntime runtime; runtime.handler_context=&context; runtime.browser_control=&control; runtime.bookmark_store=&bookmarks; runtime.history_store=&history; runtime.console_store=&console; runtime.network_store=&network; runtime.device_info_provider=&device_info;
  runtime.set_home=[](std::string){ return kelpie::BrowserControlResult::Success(); }; runtime.get_home=[](std::string* url){ *url="https://home.test"; return kelpie::BrowserControlResult::Success(); }; runtime.show_native_toast=[](std::string){ return kelpie::BrowserControlResult::Success(); }; runtime.set_native_fullscreen=[](bool){ return kelpie::BrowserControlResult::Success(); }; runtime.get_native_fullscreen=[](bool* enabled){ *enabled=true; return kelpie::BrowserControlResult::Success(); }; runtime.request_shutdown=[](){ return kelpie::BrowserControlResult::Success(); };
  runtime.renderer_supplier=[](){return kelpie::SuccessResponse({{"current","chromium"},{"available",{"chromium"}}});};
  runtime.viewport_supplier=[&](){return nlohmann::json{{"width",width},{"height",height},{"devicePixelRatio",1.0}};}; runtime.resize_viewport=[&](int w,int h){width=w;height=h;return true;}; runtime.reset_viewport=[&](){width=1280;height=720;return true;};
  kelpie::DesktopRouter router; kelpie::BookmarkHandler bookmark_handler(runtime); kelpie::HistoryHandler history_handler(runtime); kelpie::RendererHandler renderer_handler(runtime); kelpie::ViewportHandler viewport_handler(runtime); kelpie::DomHandler dom(runtime); kelpie::EvaluateHandler evaluate(runtime); kelpie::InteractionHandler interaction(runtime); kelpie::CookieHandler cookies(runtime); kelpie::DialogHandler dialogs(runtime); kelpie::InspectionHandler inspection(runtime); kelpie::ConsoleHandler console_handler(runtime); kelpie::NetworkHandler network_handler(runtime); kelpie::ShellHandler shell(runtime); kelpie::DeviceHandler device_handler(runtime); kelpie::BrowserManagementHandler browser_handler(runtime); kelpie::PartitionHandler partition_handler(runtime); kelpie::NavigationHandler navigation_handler(runtime);
  bookmark_handler.Register(router); history_handler.Register(router); renderer_handler.Register(router); viewport_handler.Register(router); dom.Register(router); evaluate.Register(router); interaction.Register(router); cookies.Register(router); dialogs.Register(router); inspection.Register(router); console_handler.Register(router); network_handler.Register(router); shell.Register(router); device_handler.Register(router); browser_handler.Register(router); partition_handler.Register(router); navigation_handler.Register(router);
  auto add=router.Dispatch("bookmarks-add",{{"url","https://example.com"},{"title","Example"}}); assert(add.status_code==200); assert(add.body["bookmarks"].size()==1);
  assert(router.Dispatch("get-bookmarks",nlohmann::json::object()).body["bookmarks"].size()==1); history.Record("https://example.com","Example"); assert(router.Dispatch("get-history",{{"limit",10}}).body["entries"].size()==1);
  assert(router.Dispatch("get-renderer",nlohmann::json::object()).body["current"]=="chromium"); assert(router.Dispatch("resize-viewport",{{"width",390},{"height",844}}).body["viewport"]["width"]==390); assert(router.Dispatch("reset-viewport",nlohmann::json::object()).body["viewport"]["width"]==1280);
  assert(router.Dispatch("resize-viewport",{{"width","390"},{"height",844}}).status_code==400); assert(router.Dispatch("resize-viewport",{{"width",0},{"height",844}}).status_code==400); assert(router.Dispatch("get-viewport",{{"tabId","second"}}).status_code==400);
  // A whole number past `int` was narrowed silently, so 4294967297 arrived as 1
  // and satisfied the bounds it should have failed.
  assert(router.Dispatch("resize-viewport",{{"width",4294967297LL},{"height",844}}).status_code==400);
  assert(router.Dispatch("resize-viewport",{{"width",390},{"height",-4294967295LL}}).status_code==400);
  assert(router.Dispatch("set-home", {{"url", "https://home.test"}}).status_code == 200); assert(router.Dispatch("get-home", nlohmann::json::object()).body["url"] == "https://home.test"); assert(router.Dispatch("toast", {{"message", "ready"}}).status_code == 200); assert(router.Dispatch("set-fullscreen", {{"enabled", true}}).status_code == 200); assert(router.Dispatch("get-fullscreen", nlohmann::json::object()).body["fullscreen"] == true); assert(router.Dispatch("close-browser", nlohmann::json::object()).body["accepted"] == true);
  const nlohmann::json second={{"tabId","second"},{"generation",9}};
  auto dom_result=router.Dispatch("query-selector",{{"tabId","second"},{"generation",9},{"selector","div"}}); assert(dom_result.status_code==200); assert(control.last_lease.id=="second" && control.last_lease.generation==9);
  auto cookie_result=router.Dispatch("get-cookies",second); assert(cookie_result.status_code==200 && control.last_lease.id=="second");
  assert(router.Dispatch("set-cookie",{{"tabId","second"},{"generation",9},{"name","empty"},{"value",""},{"sameSite","lax"}}).status_code==200);
  assert(control.last_cookie["sameSite"] == "Lax");
  assert(router.Dispatch("set-cookie",{{"tabId","second"},{"generation",9},{"name","bad"},{"value",""},{"sameSite","invalid"}}).status_code==400);
  assert(router.Dispatch("delete-cookies",{{"tabId","second"},{"generation",9},{"domain","example.test"}}).status_code==200);
  assert(router.Dispatch("set-storage",{{"tabId","second"},{"generation",9},{"key","empty"},{"value",""}}).status_code==200);
  assert(router.Dispatch("fill",{{"tabId","second"},{"generation",9},{"selector","#name"},{"value",""}}).status_code==200);
  auto dialog_result=router.Dispatch("handle-dialog",{{"tabId","second"},{"generation",9},{"action","accept"}}); assert(dialog_result.status_code==200 && control.last_lease.id=="second");
  assert(dialog_result.body["action"]=="accept" && dialog_result.body["dialogType"]=="confirm");
  auto shown=router.Dispatch("get-dialog",{{"tabId","second"},{"generation",9}}); assert(shown.body["showing"]==true && shown.body["dialog"]["type"]=="alert");
  assert(router.Dispatch("get-console-messages",{{"tabId","second"}}).status_code==400); assert(router.Dispatch("get-network-log",{{"generation",9}}).status_code==400);
  auto bad_generation=router.Dispatch("get-page-text",{{"generation","nine"}}); assert(bad_generation.status_code==400);
  auto bad_storage=router.Dispatch("get-storage",{{"type",7}}); assert(bad_storage.status_code==400);
  assert(router.Dispatch("resize-viewport", {{"width", 4294967297ULL}, {"height", 720}}).status_code == 400);
  assert(router.Dispatch("get-console-messages", {{"limit", "many"}}).status_code == 400);
  assert(router.Dispatch("wait-for-element", {{"selector", "#ready"}, {"state", "visible"}, {"tabId", "second"}, {"generation", 9}}).body["state"] == "visible");
  // Completion is an engine-tracked request, not an old document.readyState.
  assert(router.Dispatch("wait-for-navigation", second).status_code == 200);
  control.nav_polls = 0; control.nav_requested = 2; control.nav_completed = 0;
  assert(router.Dispatch("wait-for-navigation", second).status_code == 200);
  control.nav_error = "DNS failed"; control.nav_requested = 3; control.nav_completed = 0; control.nav_polls = 0;
  assert(router.Dispatch("wait-for-navigation", second).status_code == 502); control.nav_error.clear(); control.nav_completed = 3;
  // navigate answers only once its load has finished (docs/api/core.md).
  control.nav_polls = 0; control.nav_requested = 4; control.nav_completed = 0;
  auto loaded = router.Dispatch("navigate", {{"url", "https://two.test"}});
  assert(loaded.status_code == 200 && control.nav_completed == 4 && control.nav_polls >= 2 && loaded.body.contains("loadTime"));
  control.nav_error = "DNS failed"; control.nav_requested = 5; control.nav_completed = 0; control.nav_polls = 0;
  assert(router.Dispatch("navigate", {{"url", "https://two.test"}}).status_code == 502); control.nav_error.clear(); control.nav_completed = 5;
  auto a11y=router.Dispatch("get-accessibility-tree", {{"tabId", "second"}, {"generation", 9}, {"interactableOnly", true}, {"maxDepth", 2}});
  assert(a11y.status_code == 200 && control.last_devtools_method == "Accessibility.getFullAXTree" && a11y.body["count"] == 1);
  assert(router.Dispatch("find-input", {{"tabId", "second"}, {"generation", 9}, {"placeholder", "Email"}}).status_code == 200);
  assert(router.Dispatch("find-input", {{"tabId", "second"}, {"generation", 9}}).status_code == 400);
  // get-device-info must answer 200: the router keys the HTTP status and the
  // MCP isError flag off `success`, so a bare provider payload became a 400.
  auto device=router.Dispatch("get-device-info", nlohmann::json::object());
  assert(device.status_code==200);
  assert(device.body["success"]==true);
  assert(device.body["name"]=="Stub Desktop");
  // --- Storage partitions ---------------------------------------------------
  // A plain new-tab stays in the default store and reports no partition fields.
  auto plain_tab=router.Dispatch("new-tab",{{"url","https://example.test"}});
  assert(plain_tab.status_code==200);
  assert(!plain_tab.body["tab"].contains("partition") && !plain_tab.body["tab"].contains("name"));
  assert(!plain_tab.body["tab"].contains("persistent"));
  assert(!control.last_new_tab.partition.has_value() && control.last_new_tab.persistent);
  // name/partition/persistent travel through to the engine and back out again.
  auto isolated=router.Dispatch("new-tab",{{"url","https://example.test"},{"name","Sam"},{"partition","sam.eng-lead"},{"persistent",false}});
  assert(isolated.status_code==200);
  assert(isolated.body["tab"]["partition"]=="sam.eng-lead");
  assert(isolated.body["tab"]["name"]=="Sam");
  assert(isolated.body["tab"]["persistent"]==false);
  assert(control.last_new_tab.partition && *control.last_new_tab.partition=="sam.eng-lead");
  assert(!control.last_new_tab.persistent);
  // Every rejection the shared validator makes is a 400 INVALID_PARTITION, not
  // a generic INVALID_PARAMS, and the message names the offending string.
  for (const char* rejected : {"has space", "default", "ephemeral-1", "...", ""}) {
    auto invalid=router.Dispatch("new-tab",{{"partition",rejected}});
    assert(invalid.status_code==400);
    assert(invalid.body["error"]["code"]=="INVALID_PARTITION");
    assert(invalid.body["error"]["message"].get<std::string>().find(rejected)!=std::string::npos);
  }
  assert(router.Dispatch("new-tab",{{"partition",7}}).status_code==400);
  assert(router.Dispatch("new-tab",{{"name",std::string(201,'x')}}).status_code==400);
  assert(router.Dispatch("new-tab",{{"name",std::string(200,'x')}}).status_code==200);
  assert(router.Dispatch("new-tab",{{"persistent","yes"}}).status_code==400);
  // A partition mid-teardown refuses the tab rather than binding it to a store
  // that is about to disappear.
  control.partition_deleting=true;
  auto deleting=router.Dispatch("new-tab",{{"partition","sam.eng-lead"}});
  assert(deleting.status_code==409 && deleting.body["error"]["code"]=="PARTITION_DELETING");
  control.partition_deleting=false;
  auto listed=router.Dispatch("get-partitions",nlohmann::json::object());
  assert(listed.status_code==200 && listed.body["partitions"].size()==2);
  assert(listed.body["partitions"][0]["id"]=="work" && listed.body["partitions"][0]["tabCount"]==2);
  assert(listed.body["partitions"][0]["persistent"]==true);
  assert(listed.body["partitions"][1]["persistent"]==false);
  assert(!listed.body["partitions"][0].contains("sizeBytes"));
  assert(router.Dispatch("get-partitions",{{"tabId","second"}}).status_code==400);
  auto deleted=router.Dispatch("delete-partition",{{"id","work"}});
  assert(deleted.status_code==200 && deleted.body["deleted"]=="work");
  assert(deleted.body["tabsClosed"]==2 && deleted.body["existed"]==true);
  // Idempotent: a second delete is a success that admits the id was unknown.
  auto again=router.Dispatch("delete-partition",{{"id","gone-1"}});
  assert(again.status_code==200 && again.body["existed"]==false && again.body["tabsClosed"]==0);
  assert(router.Dispatch("delete-partition",nlohmann::json::object()).status_code==400);
  // An engine with no partition support says so, with a reason to act on.
  control.partitions_supported=false;
  auto unsupported=router.Dispatch("get-partitions",nlohmann::json::object());
  assert(unsupported.status_code==501 && unsupported.body["error"]["code"]=="PARTITION_UNSUPPORTED");
  assert(unsupported.body["error"]["reason"]=="platform-single-tab");
  control.partitions_supported=true;
  // get-tabs carries the same fields, and omits them for an unpartitioned tab.
  control.second.partition="sam.eng-lead"; control.second.name="Sam"; control.second.persistent=true;
  auto tabs_listed=router.Dispatch("get-tabs",nlohmann::json::object());
  assert(tabs_listed.status_code==200 && tabs_listed.body["tabs"].size()==2);
  assert(!tabs_listed.body["tabs"][0].contains("partition"));
  assert(tabs_listed.body["tabs"][1]["partition"]=="sam.eng-lead");
  assert(tabs_listed.body["tabs"][1]["name"]=="Sam");
  control.second.partition.reset(); control.second.name.reset(); control.second.persistent.reset();

  control.stale=true; auto stale=router.Dispatch("get-dialog",second); assert(stale.body["error"]["code"]=="TAB_STALE"); control.stale=false;
  control.timeout_eval=true; auto timeout=router.Dispatch("get-page-text",second); assert(timeout.status_code==408 && timeout.body["error"]["code"]=="TIMEOUT");
  return 0;
}
