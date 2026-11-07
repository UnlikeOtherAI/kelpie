#include "scroll_handler.h"

namespace kelpie {

ScrollHandler::ScrollHandler(DesktopHandlerRuntime runtime) : runtime_(std::move(runtime)) {}

void ScrollHandler::Register(DesktopRouter& router) const {
  router.Register("scroll", [this](const nlohmann::json& params) { return Scroll(params); });
  router.Register("scroll-to-top",
                  [this](const nlohmann::json& p) { return ScrollTo(p, "window.scrollTo(0, 0)"); });
  router.Register("scroll-to-bottom",
                  [this](const nlohmann::json& p) {
                    return ScrollTo(p, "window.scrollTo(0, document.documentElement.scrollHeight)");
                  });
  router.Register("scroll2", [](const nlohmann::json&) { return Unsupported("scroll2"); }, false);
}

nlohmann::json ScrollHandler::Scroll(const nlohmann::json& params) const {
  try {
  const double delta_x = RequireNumber(params, "deltaX");
  const double delta_y = RequireNumber(params, "deltaY");
  const std::string script =
      "(() => {"
      "window.scrollBy(" + std::to_string(delta_x) + ", " + std::to_string(delta_y) + ");"
      "return {scrollX: window.scrollX, scrollY: window.scrollY};"
      "})()";
  nlohmann::json result; const auto control = EvaluateForTab(runtime_, params, script, &result);
  if (!control.ok) return ControlError(control);
  return SuccessResponse({
      {"scrollX", result.value("scrollX", delta_x)},
      {"scrollY", result.value("scrollY", delta_y)},
  }); } catch (const std::invalid_argument& e) { return InvalidParams(e.what()); }
}

nlohmann::json ScrollHandler::ScrollTo(const nlohmann::json& params, const std::string& expression) const {
  const std::string script =
      "(() => {" + expression + "; return {scrollY: window.scrollY}; })()";
  nlohmann::json result; const auto control = EvaluateForTab(runtime_, params, script, &result);
  if (!control.ok) return ControlError(control);
  return SuccessResponse({{"scrollY", result.value("scrollY", 0)}});
}

}  // namespace kelpie
