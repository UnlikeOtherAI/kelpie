#include "scroll_handler.h"

namespace kelpie {

ScrollHandler::ScrollHandler(DesktopHandlerRuntime runtime) : runtime_(std::move(runtime)) {}

void ScrollHandler::Register(DesktopRouter& router) const {
  router.Register("scroll", [this](const nlohmann::json& params) { return Scroll(params); });
  router.Register("scroll-to-top",
                  [this](const nlohmann::json&) { return ScrollTo("window.scrollTo(0, 0)"); });
  router.Register("scroll-to-bottom",
                  [this](const nlohmann::json&) {
                    return ScrollTo("window.scrollTo(0, document.documentElement.scrollHeight)");
                  });
  router.Register("scroll2", [](const nlohmann::json&) { return Unsupported("scroll2"); });
}

nlohmann::json ScrollHandler::Scroll(const nlohmann::json& params) const {
  HandlerContext& context = RequireHandlerContext(runtime_);
  const int delta_x = IntOrDefault(params, "deltaX", 0);
  const int delta_y = IntOrDefault(params, "deltaY", 0);
  const std::string script =
      "(() => {"
      "window.scrollBy(" + std::to_string(delta_x) + ", " + std::to_string(delta_y) + ");"
      "return {scrollX: window.scrollX, scrollY: window.scrollY};"
      "})()";
  const nlohmann::json result = context.EvaluateJsReturningJson(script);
  return SuccessResponse({
      {"scrollX", result.value("scrollX", delta_x)},
      {"scrollY", result.value("scrollY", delta_y)},
  });
}

nlohmann::json ScrollHandler::ScrollTo(const std::string& expression) const {
  HandlerContext& context = RequireHandlerContext(runtime_);
  const std::string script =
      "(() => {" + expression + "; return {scrollY: window.scrollY}; })()";
  const nlohmann::json result = context.EvaluateJsReturningJson(script);
  return SuccessResponse({{"scrollY", result.value("scrollY", 0)}});
}

}  // namespace kelpie
