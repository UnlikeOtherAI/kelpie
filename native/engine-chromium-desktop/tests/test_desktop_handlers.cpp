#include "kelpie/cef_renderer.h"

#include <cassert>
#include <cstdlib>
#undef assert
#define assert(expression) do { if (!(expression)) std::abort(); } while (false)

#include "kelpie/desktop_router.h"
#include "kelpie/handler_context.h"
#include "handlers/bookmark_handler.h"
#include "handlers/cookie_handler.h"
#include "handlers/console_handler.h"
#include "handlers/dialog_handler.h"
#include "handlers/dom_handler.h"
#include "handlers/evaluate_handler.h"
#include "handlers/history_handler.h"
#include "handlers/inspection_handler.h"
#include "handlers/interaction_handler.h"
#include "handlers/network_handler.h"
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
  kelpie::TabLease last_lease; bool stale = false; bool timeout_eval = false;
  kelpie::TabSnapshot first{"first", 3, "https://one.test", "One", true};
  kelpie::TabSnapshot second{"second", 9, "https://two.test", "Two", false};
  kelpie::BrowserControlResult GetTabs(std::vector<kelpie::TabSnapshot>* tabs, Timeout) override { *tabs={first,second}; return kelpie::BrowserControlResult::Success(); }
  kelpie::BrowserControlResult ResolveTab(const std::optional<std::string>& id, const std::optional<std::uint64_t>& gen, kelpie::TabLease* lease, Timeout) override {
    if (stale || (gen && ((id && *id == "second" && *gen != 9) || (!id && *gen != 3)))) return kelpie::BrowserControlResult::Failure("TAB_STALE", "tab lease is stale");
    const auto& tab = id && *id == "second" ? second : first; *lease={tab.id,tab.generation}; last_lease=*lease; return kelpie::BrowserControlResult::Success(tab);
  }
  kelpie::BrowserControlResult CreateTab(std::string, kelpie::TabSnapshot* tab, Timeout) override { *tab=second; return kelpie::BrowserControlResult::Success(second); }
  kelpie::BrowserControlResult ActivateTab(kelpie::TabLease lease, Timeout) override { last_lease=lease; return kelpie::BrowserControlResult::Success(second); }
  kelpie::BrowserControlResult CloseTab(kelpie::TabLease lease, Timeout) override { last_lease=lease; return kelpie::BrowserControlResult::Success(second); }
  kelpie::BrowserControlResult Navigate(std::optional<kelpie::TabLease> lease, std::string, kelpie::TabSnapshot* tab, Timeout) override { last_lease=*lease; *tab=first; return kelpie::BrowserControlResult::Success(first); }
  kelpie::BrowserControlResult Back(kelpie::TabLease lease, kelpie::TabSnapshot* tab, Timeout) override { last_lease=lease; *tab=first; return kelpie::BrowserControlResult::Success(first); }
  kelpie::BrowserControlResult Forward(kelpie::TabLease lease, kelpie::TabSnapshot* tab, Timeout) override { last_lease=lease; *tab=first; return kelpie::BrowserControlResult::Success(first); }
  kelpie::BrowserControlResult Reload(kelpie::TabLease lease, kelpie::TabSnapshot* tab, Timeout) override { last_lease=lease; *tab=first; return kelpie::BrowserControlResult::Success(first); }
  kelpie::BrowserControlResult Evaluate(kelpie::TabLease lease, std::string script, Json* value, Timeout) override { last_lease=lease; if(timeout_eval) return kelpie::BrowserControlResult::Failure("TIMEOUT","evaluation timed out"); if(script.find("readyState")!=std::string::npos) *value="complete"; else if(script.find("found")!=std::string::npos) *value={{"found",true},{"text","matched"}}; else *value={{"elements",nlohmann::json::array()},{"count",0}}; return kelpie::BrowserControlResult::Success(lease.id=="second"?second:first); }
  kelpie::BrowserControlResult Screenshot(kelpie::TabLease lease, kelpie::BrowserScreenshot* image, Timeout) override { last_lease=lease; image->base64_data="AA=="; return kelpie::BrowserControlResult::Success(second); }
  kelpie::BrowserControlResult GetCookies(kelpie::TabLease lease, const Json&, Json* out, Timeout) override { last_lease=lease; *out=nlohmann::json::array({{{"name","a"},{"value","b"}}}); return kelpie::BrowserControlResult::Success(second); }
  kelpie::BrowserControlResult SetCookies(kelpie::TabLease lease, const Json&, Json* out, Timeout) override { last_lease=lease; *out={{"set",true}}; return kelpie::BrowserControlResult::Success(second); }
  kelpie::BrowserControlResult DeleteCookies(kelpie::TabLease lease, const Json&, Json* out, Timeout) override { last_lease=lease; *out={{"deleted",1}}; return kelpie::BrowserControlResult::Success(second); }
  kelpie::BrowserControlResult DispatchTrustedInput(kelpie::TabLease lease, const Json&, Json* out, Timeout) override { last_lease=lease; *out={{"trusted",true}}; return kelpie::BrowserControlResult::Success(second); }
  kelpie::BrowserControlResult GetDialog(kelpie::TabLease lease, Json* out, Timeout) override { last_lease=lease; *out={{"open",true},{"type","alert"}}; return kelpie::BrowserControlResult::Success(second); }
  kelpie::BrowserControlResult HandleDialog(kelpie::TabLease lease, const Json&, Json* out, Timeout) override { last_lease=lease; *out={{"handled",true}}; return kelpie::BrowserControlResult::Success(second); }
  kelpie::BrowserControlResult DevTools(kelpie::TabLease lease, std::string, const Json&, Json* out, Timeout) override { last_lease=lease; *out=nlohmann::json::object(); return kelpie::BrowserControlResult::Success(second); }
};
}  // namespace

int main() {
  kelpie::CefRenderer renderer; kelpie::HandlerContext context(&renderer); kelpie::BookmarkStore bookmarks; kelpie::HistoryStore history; kelpie::ConsoleStore console; kelpie::NetworkTrafficStore network; StubDeviceInfoProvider device_info; MockControl control;
  int width=1280,height=720;
  kelpie::DesktopHandlerRuntime runtime; runtime.handler_context=&context; runtime.browser_control=&control; runtime.bookmark_store=&bookmarks; runtime.history_store=&history; runtime.console_store=&console; runtime.network_store=&network; runtime.device_info_provider=&device_info;
  runtime.set_home=[](std::string){ return kelpie::BrowserControlResult::Success(); }; runtime.get_home=[](std::string* url){ *url="https://home.test"; return kelpie::BrowserControlResult::Success(); }; runtime.show_native_toast=[](std::string){ return kelpie::BrowserControlResult::Success(); }; runtime.set_native_fullscreen=[](bool){ return kelpie::BrowserControlResult::Success(); }; runtime.get_native_fullscreen=[](bool* enabled){ *enabled=true; return kelpie::BrowserControlResult::Success(); }; runtime.request_shutdown=[](){ return kelpie::BrowserControlResult::Success(); };
  runtime.renderer_supplier=[](){return kelpie::SuccessResponse({{"current","chromium"},{"available",{"chromium"}}});};
  runtime.viewport_supplier=[&](){return nlohmann::json{{"width",width},{"height",height},{"devicePixelRatio",1.0}};}; runtime.resize_viewport=[&](int w,int h){width=w;height=h;return true;}; runtime.reset_viewport=[&](){width=1280;height=720;};
  kelpie::DesktopRouter router; kelpie::BookmarkHandler bookmark_handler(runtime); kelpie::HistoryHandler history_handler(runtime); kelpie::RendererHandler renderer_handler(runtime); kelpie::ViewportHandler viewport_handler(runtime); kelpie::DomHandler dom(runtime); kelpie::EvaluateHandler evaluate(runtime); kelpie::InteractionHandler interaction(runtime); kelpie::CookieHandler cookies(runtime); kelpie::DialogHandler dialogs(runtime); kelpie::InspectionHandler inspection(runtime); kelpie::ConsoleHandler console_handler(runtime); kelpie::NetworkHandler network_handler(runtime); kelpie::ShellHandler shell(runtime);
  bookmark_handler.Register(router); history_handler.Register(router); renderer_handler.Register(router); viewport_handler.Register(router); dom.Register(router); evaluate.Register(router); interaction.Register(router); cookies.Register(router); dialogs.Register(router); inspection.Register(router); console_handler.Register(router); network_handler.Register(router); shell.Register(router);
  auto add=router.Dispatch("bookmarks-add",{{"url","https://example.com"},{"title","Example"}}); assert(add.status_code==200); assert(add.body["bookmarks"].size()==1);
  assert(router.Dispatch("get-bookmarks",nlohmann::json::object()).body["bookmarks"].size()==1); history.Record("https://example.com","Example"); assert(router.Dispatch("get-history",{{"limit",10}}).body["entries"].size()==1);
  assert(router.Dispatch("get-renderer",nlohmann::json::object()).body["current"]=="chromium"); assert(router.Dispatch("resize-viewport",{{"width",390},{"height",844}}).body["viewport"]["width"]==390); assert(router.Dispatch("reset-viewport",nlohmann::json::object()).body["viewport"]["width"]==1280);
  assert(router.Dispatch("resize-viewport",{{"width","390"},{"height",844}}).status_code==400); assert(router.Dispatch("resize-viewport",{{"width",0},{"height",844}}).status_code==400); assert(router.Dispatch("get-viewport",{{"tabId","second"}}).status_code==400);
  assert(router.Dispatch("set-home", {{"url", "https://home.test"}}).status_code == 200); assert(router.Dispatch("get-home", nlohmann::json::object()).body["url"] == "https://home.test"); assert(router.Dispatch("toast", {{"message", "ready"}}).status_code == 200); assert(router.Dispatch("set-fullscreen", {{"enabled", true}}).status_code == 200); assert(router.Dispatch("get-fullscreen", nlohmann::json::object()).body["fullscreen"] == true); assert(router.Dispatch("close-browser", nlohmann::json::object()).body["accepted"] == true);
  const nlohmann::json second={{"tabId","second"},{"generation",9}};
  auto dom_result=router.Dispatch("query-selector",{{"tabId","second"},{"generation",9},{"selector","div"}}); assert(dom_result.status_code==200); assert(control.last_lease.id=="second" && control.last_lease.generation==9);
  auto cookie_result=router.Dispatch("get-cookies",second); assert(cookie_result.status_code==200 && control.last_lease.id=="second");
  assert(router.Dispatch("set-cookie",{{"tabId","second"},{"generation",9},{"name","empty"},{"value",""}}).status_code==200);
  assert(router.Dispatch("set-storage",{{"tabId","second"},{"generation",9},{"key","empty"},{"value",""}}).status_code==200);
  assert(router.Dispatch("fill",{{"tabId","second"},{"generation",9},{"selector","#name"},{"value",""}}).status_code==200);
  auto dialog_result=router.Dispatch("handle-dialog",{{"tabId","second"},{"generation",9},{"action","accept"}}); assert(dialog_result.status_code==200 && control.last_lease.id=="second");
  assert(router.Dispatch("get-console-messages",{{"tabId","second"}}).status_code==400); assert(router.Dispatch("get-network-log",{{"generation",9}}).status_code==400);
  auto bad_generation=router.Dispatch("get-page-text",{{"generation","nine"}}); assert(bad_generation.status_code==400);
  auto bad_storage=router.Dispatch("get-storage",{{"type",7}}); assert(bad_storage.status_code==400);
  control.stale=true; auto stale=router.Dispatch("get-dialog",second); assert(stale.body["error"]["code"]=="TAB_STALE"); control.stale=false;
  control.timeout_eval=true; auto timeout=router.Dispatch("get-page-text",second); assert(timeout.status_code==408 && timeout.body["error"]["code"]=="TIMEOUT");
  return 0;
}
