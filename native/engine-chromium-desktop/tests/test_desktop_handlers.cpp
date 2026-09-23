#include "kelpie/cef_renderer.h"

#include <cassert>
#include <cmath>
#include <cstdlib>
#include <thread>
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
#include "handlers/screenshot_handler.h"
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
  kelpie::TabLease last_lease; nlohmann::json last_cookie; std::string last_devtools_method; nlohmann::json last_devtools_params; bool stale = false; bool timeout_eval = false;
  // One finished page load, as a fresh tab has after its first page.
  kelpie::NavigationTracker nav{1, 1, 0, {}}; bool nav_stops_on_second_poll = false; int nav_polls = 0;
  // The order the handlers called the engine in, for the baseline checks.
  std::vector<std::string> calls;
  kelpie::BrowserControlResult MarkNavigationAction(kelpie::TabLease lease, Timeout) override {
    last_lease=lease; calls.push_back("mark"); nav.MarkAction(); return kelpie::BrowserControlResult::Success();
  }
  kelpie::TabSnapshot first{"first", 3, "https://one.test", "One", true};
  kelpie::TabSnapshot second{"second", 9, "https://two.test", "Two", false};
  kelpie::BrowserControlResult GetTabs(std::vector<kelpie::TabSnapshot>* tabs, Timeout) override { *tabs={first,second}; return kelpie::BrowserControlResult::Success(); }
  // Models a UI thread too busy to answer a poll given only the last few
  // milliseconds of a wait: like RunOnUi, it waits out that budget, then times out.
  bool nav_poll_starved = false;
  kelpie::BrowserControlResult GetNavigationState(kelpie::TabLease lease, kelpie::BrowserNavigationState* state, Timeout timeout) override {
    if (nav_poll_starved && timeout < std::chrono::milliseconds(80)) {
      std::this_thread::sleep_for(timeout);
      return kelpie::BrowserControlResult::Failure("TIMEOUT", "Browser operation timed out");
    }
    ++nav_polls;
    if (nav_stops_on_second_poll && nav_polls >= 2) nav.LoadStopped();
    *state = {lease.id == "second" ? second : first, nav};
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
  // Like the engine, an API navigation moves the baseline and starts a load;
  // `nav_load_error` makes that load fail before it commits.
  std::string nav_load_error;
  kelpie::BrowserControlResult Navigate(std::optional<kelpie::TabLease> lease, std::string, kelpie::TabSnapshot* tab, Timeout) override { last_lease=*lease; nav.ApiNavigationRequested(); if (!nav_load_error.empty()) nav.LoadFailed(nav_load_error); *tab=first; return kelpie::BrowserControlResult::Success(first); }
  kelpie::BrowserControlResult Back(kelpie::TabLease lease, kelpie::TabSnapshot* tab, Timeout) override { last_lease=lease; *tab=first; return kelpie::BrowserControlResult::Success(first); }
  kelpie::BrowserControlResult Forward(kelpie::TabLease lease, kelpie::TabSnapshot* tab, Timeout) override { last_lease=lease; *tab=first; return kelpie::BrowserControlResult::Success(first); }
  kelpie::BrowserControlResult Reload(kelpie::TabLease lease, kelpie::TabSnapshot* tab, Timeout) override { last_lease=lease; *tab=first; return kelpie::BrowserControlResult::Success(first); }
  kelpie::BrowserControlResult Evaluate(kelpie::TabLease lease, std::string script, Json* value, Timeout) override { last_lease=lease; calls.push_back("evaluate"); if(timeout_eval) return kelpie::BrowserControlResult::Failure("TIMEOUT","evaluation timed out"); if(script.find("readyState")!=std::string::npos) *value="complete"; else if(script.find("attached")!=std::string::npos) *value={{"attached",true},{"visible",true},{"text","matched"}}; else if(script.find("found")!=std::string::npos) *value={{"found",true},{"text","matched"}}; else *value={{"elements",nlohmann::json::array()},{"count",0}}; return kelpie::BrowserControlResult::Success(lease.id=="second"?second:first); }
  kelpie::BrowserScreenshotOptions last_screenshot; bool minimized = false;
  kelpie::BrowserControlResult Screenshot(kelpie::TabLease lease, const kelpie::BrowserScreenshotOptions& options, kelpie::BrowserScreenshot* image, Timeout) override {
    last_lease=lease; last_screenshot=options;
    if (minimized) return kelpie::BrowserControlResult::Failure("WINDOW_MINIMIZED", "The browser window is minimised");
    image->base64_data="AA=="; image->mime_type="image/"+options.format; image->width=960; image->height=479;
    image->viewport_width=1918; image->viewport_height=957; image->device_pixel_ratio=1; image->image_scale=960.0/1918.0;
    return kelpie::BrowserControlResult::Success(second);
  }
  kelpie::BrowserControlResult GetCookies(kelpie::TabLease lease, const Json&, Json* out, Timeout) override { last_lease=lease; *out=nlohmann::json::array({{{"name","a"},{"value","b"}}}); return kelpie::BrowserControlResult::Success(second); }
  kelpie::BrowserControlResult SetCookies(kelpie::TabLease lease, const Json& cookies, Json* out, Timeout) override { last_lease=lease; last_cookie=cookies; *out={{"set",true}}; return kelpie::BrowserControlResult::Success(second); }
  kelpie::BrowserControlResult DeleteCookies(kelpie::TabLease lease, const Json&, Json* out, Timeout) override { last_lease=lease; *out={{"deleted",1}}; return kelpie::BrowserControlResult::Success(second); }
  kelpie::BrowserControlResult DispatchTrustedInput(kelpie::TabLease lease, const Json&, Json* out, Timeout) override { last_lease=lease; calls.push_back("input"); *out={{"trusted",true}}; return kelpie::BrowserControlResult::Success(second); }
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
  kelpie::DesktopRouter router; kelpie::BookmarkHandler bookmark_handler(runtime); kelpie::HistoryHandler history_handler(runtime); kelpie::RendererHandler renderer_handler(runtime); kelpie::ViewportHandler viewport_handler(runtime); kelpie::DomHandler dom(runtime); kelpie::EvaluateHandler evaluate(runtime); kelpie::InteractionHandler interaction(runtime); kelpie::CookieHandler cookies(runtime); kelpie::DialogHandler dialogs(runtime); kelpie::InspectionHandler inspection(runtime); kelpie::ConsoleHandler console_handler(runtime); kelpie::NetworkHandler network_handler(runtime); kelpie::ShellHandler shell(runtime); kelpie::DeviceHandler device_handler(runtime); kelpie::BrowserManagementHandler browser_handler(runtime); kelpie::PartitionHandler partition_handler(runtime); kelpie::NavigationHandler navigation_handler(runtime); kelpie::ScreenshotHandler screenshot_handler(runtime);
  bookmark_handler.Register(router); history_handler.Register(router); renderer_handler.Register(router); viewport_handler.Register(router); dom.Register(router); evaluate.Register(router); interaction.Register(router); cookies.Register(router); dialogs.Register(router); inspection.Register(router); console_handler.Register(router); network_handler.Register(router); shell.Register(router); device_handler.Register(router); browser_handler.Register(router); partition_handler.Register(router); navigation_handler.Register(router); screenshot_handler.Register(router);
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
  // Completion is engine-tracked navigation state, not an old document.readyState.
  // A fresh tab has had no action, so its first page load counts. (The fill
  // above was an action, so the tracker is reset to a fresh tab first.)
  control.nav = kelpie::NavigationTracker{1, 1, 0, {}};
  assert(router.Dispatch("wait-for-navigation", second).status_code == 200);
  // Each input moves the baseline before it is dispatched, so a navigation the
  // page starts in response is the one a later wait waits for.
  control.calls.clear();
  assert(router.Dispatch("click", {{"tabId", "second"}, {"generation", 9}, {"selector", "#next"}}).status_code == 200);
  assert((control.calls == std::vector<std::string>{"mark", "input"}));
  assert(control.nav.baseline == 1);
  // The click did not navigate: the earlier page load is not returned as a
  // stale success, and the timeout says nothing started.
  auto idle = router.Dispatch("wait-for-navigation", {{"tabId", "second"}, {"generation", 9}, {"timeout", 150}});
  assert(idle.status_code == 408 && idle.body["error"]["code"] == "TIMEOUT");
  assert(idle.body["error"]["message"] == "No navigation started within 150 ms");
  // The last poll only gets what is left of the wait. When that poll times out
  // at the deadline, the caller still learns that no navigation started,
  // rather than a generic "Browser operation timed out".
  control.nav_poll_starved = true;
  auto starved = router.Dispatch("wait-for-navigation", {{"tabId", "second"}, {"generation", 9}, {"timeout", 150}});
  control.nav_poll_starved = false;
  assert(starved.status_code == 408 && starved.body["error"]["message"] == "No navigation started within 150 ms");
  // The page commits a navigation, and the wait returns once loading stops.
  control.nav.LoadStarted(); control.nav_polls = 0; control.nav_stops_on_second_poll = true;
  assert(router.Dispatch("wait-for-navigation", second).status_code == 200);
  control.nav_stops_on_second_poll = false;
  control.nav.MarkAction(); control.nav.LoadFailed("DNS failed"); control.nav.LoadStopped();
  auto failed = router.Dispatch("wait-for-navigation", second);
  assert(failed.status_code == 502 && failed.body["error"]["message"] == "DNS failed");
  // navigate answers only once its load has finished (docs/api/core.md).
  control.nav_polls = 0; control.nav_stops_on_second_poll = true;
  auto loaded = router.Dispatch("navigate", {{"url", "https://two.test"}});
  assert(loaded.status_code == 200 && control.nav.finished == control.nav.started && control.nav_polls >= 2 && loaded.body.contains("loadTime"));
  control.nav_stops_on_second_poll = false;
  // A load that fails answers navigate with its error, not a stale success.
  control.nav_load_error = "DNS failed";
  auto unreachable = router.Dispatch("navigate", {{"url", "https://two.test"}});
  assert(unreachable.status_code == 502 && unreachable.body["error"]["message"] == "DNS failed");
  control.nav_load_error.clear();
  // A caller's script is an action too; Kelpie's own evaluations are not.
  control.calls.clear();
  assert(router.Dispatch("evaluate", {{"tabId", "second"}, {"generation", 9}, {"expression", "1"}}).status_code == 200);
  assert((control.calls == std::vector<std::string>{"mark", "evaluate"}));
  control.calls.clear();
  assert(router.Dispatch("get-page-text", second).status_code == 200);
  assert(std::find(control.calls.begin(), control.calls.end(), "mark") == control.calls.end());
  control.nav = kelpie::NavigationTracker{3, 3, 3, {}};
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
  // --- Screenshots -------------------------------------------------------------
  // The options reach the engine, and the metadata is the encoded image's own
  // size plus the CSS viewport it maps back to.
  auto shot=router.Dispatch("screenshot",{{"tabId","second"},{"generation",9},{"format","jpeg"},{"quality",60},{"maxWidth",960}});
  assert(shot.status_code==200 && shot.body["format"]=="jpeg" && shot.body["image"]=="AA==");
  assert(control.last_screenshot.format=="jpeg" && control.last_screenshot.quality==60 && control.last_screenshot.max_width==960);
  assert(shot.body["width"]==960 && shot.body["height"]==479);
  assert(shot.body["viewportWidth"]==1918 && shot.body["viewportWidth"].is_number_integer() && shot.body["viewportHeight"]==957);
  assert(shot.body["devicePixelRatio"]==1.0 && shot.body["resolution"]=="viewport");
  assert(std::abs(shot.body["imageScaleX"].get<double>() - 960.0 / 1918.0) < 1e-12);
  assert(shot.body["tab"]["id"]=="second");
  // `kelpie screenshot` always sends fullPage:false.
  assert(router.Dispatch("screenshot",{{"fullPage",false}}).status_code==200 && control.last_screenshot.format=="png");
  for (const nlohmann::json& rejected : {nlohmann::json{{"fullPage",true}}, nlohmann::json{{"format","webp"}},
                                         nlohmann::json{{"quality",0}}, nlohmann::json{{"maxWidth",16385}}}) {
    auto refused=router.Dispatch("screenshot",rejected);
    assert(refused.status_code==400 && refused.body["error"]["code"]=="INVALID_PARAMS");
  }
  // A minimised window is a 409 the caller can act on, not a stale image.
  control.minimized=true;
  auto minimized=router.Dispatch("screenshot",nlohmann::json::object());
  assert(minimized.status_code==409 && minimized.body["error"]["code"]=="WINDOW_MINIMIZED");
  assert(!minimized.body.contains("image"));
  control.minimized=false;

  control.timeout_eval=true; auto timeout=router.Dispatch("get-page-text",second); assert(timeout.status_code==408 && timeout.body["error"]["code"]=="TIMEOUT");
  return 0;
}
