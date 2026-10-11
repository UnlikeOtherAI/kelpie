#include "kelpie/desktop_core_browser.h"
#include "handlers/navigation_handler.h"
#include "handlers/interaction_handler.h"
#include "handlers/browser_mgmt_handler.h"
#include "handlers/scroll_handler.h"
#include "handlers/screenshot_handler.h"
namespace kelpie {
struct DesktopCoreBrowser::Impl {
  DesktopRouter router;
  DesktopHandlerRuntime runtime;
  NavigationHandler navigation;
  InteractionHandler interaction;
  BrowserManagementHandler tabs;
  ScrollHandler scroll;
  ScreenshotHandler screenshot;
  Impl(DesktopBrowserControl& control, HandlerContext& context)
      : runtime([&] { DesktopHandlerRuntime value; value.browser_control = &control; value.handler_context = &context; return value; }()),
        navigation(runtime), interaction(runtime), tabs(runtime), scroll(runtime), screenshot(runtime) {
    navigation.Register(router); interaction.Register(router); tabs.Register(router);
    scroll.Register(router); screenshot.Register(router);
  }
};
DesktopCoreBrowser::DesktopCoreBrowser(DesktopBrowserControl& control, HandlerContext& context)
  : impl_(std::make_unique<Impl>(control, context)) {}
DesktopCoreBrowser::~DesktopCoreBrowser() = default;
DesktopRouter& DesktopCoreBrowser::router() { return impl_->router; }
nlohmann::json EvaluateBrowserFixed(DesktopBrowserControl& control, const nlohmann::json& params) {
  try {
    TabLease lease;
    auto result = ResolveTabForRequest(control, params, &lease, ControlTimeout(params));
    if (!result.ok) return ControlError(result);
    nlohmann::json value;
    result = control.EvaluateBrowserControl(lease, RequireString(params, "expression"), &value, ControlTimeout(params));
    return result.ok ? SuccessResponse({{"result", value}}) : ControlError(result);
  } catch (...) { return ErrorResponse("COMMAND_FAILED", "Private browser reader failed"); }
}
}
