#include "screenshot_handler.h"

#include <cmath>
#include <cstdint>

#include "desktop_screenshot_planner.h"
#include "kelpie/element_selector_script.h"

namespace kelpie {

ScreenshotHandler::ScreenshotHandler(DesktopHandlerRuntime runtime)
    : runtime_(std::move(runtime)) {}

void ScreenshotHandler::Register(DesktopRouter& router) const {
  router.Register("screenshot",
                  [this](const nlohmann::json& params) { return Screenshot(params, false); });
  router.Register("screenshot-annotated",
                  [this](const nlohmann::json& params) { return Screenshot(params, true); }, false);
}

namespace {

// A CSS size is usually whole; send it as an integer then, the way iOS,
// Android and macOS do, rather than as 1918.0.
nlohmann::json CssNumber(double value) {
  const double rounded = std::round(value);
  return std::abs(value - rounded) < 1e-9 ? nlohmann::json(static_cast<std::int64_t>(rounded))
                                          : nlohmann::json(value);
}

}  // namespace

nlohmann::json ScreenshotHandler::Screenshot(const nlohmann::json& params, bool annotated) const {
  BrowserScreenshotOptions options;
  if (const auto invalid = desktop_screenshot::ParseOptions(params, &options)) return InvalidParams(*invalid);
  TabLease lease;
  auto result = RequireBrowserControl(runtime_).ResolveTab(OptionalTabId(params), OptionalGeneration(params), &lease, ControlTimeout(params));
  if (!result.ok) return ControlError(result);
  BrowserScreenshot image;
  result = RequireBrowserControl(runtime_).Screenshot(lease, options, &image, ControlTimeout(params));
  if (!result.ok) return ControlError(result);

  // The same metadata iOS, Android and macOS send: `width` and `height` are
  // the encoded image's pixels, and the scale maps them back to CSS pixels.
  nlohmann::json response = {
      {"image", image.base64_data},
      {"format", image.mime_type == "image/jpeg" ? "jpeg" : "png"},
      {"width", image.width},
      {"height", image.height},
      {"resolution", "viewport"},
      {"coordinateSpace", "viewport-css-pixels"},
      {"viewportWidth", CssNumber(image.viewport_width)},
      {"viewportHeight", CssNumber(image.viewport_height)},
      {"devicePixelRatio", image.device_pixel_ratio},
      {"imageScaleX", image.image_scale},
      {"imageScaleY", image.image_scale},
      {"tab", result.tab ? TabJson(*result.tab) : nlohmann::json::object()},
  };

  if (!annotated) {
    return SuccessResponse(response);
  }

  const std::string script =
      "(() => {" + ElementSelectorBuilderScript() +
      "return Array.from(document.querySelectorAll('a,button,input,select,textarea,[role=button]')).map((node, index) => {"
      "const rect = node.getBoundingClientRect();"
      "return {"
      "index: index + 1,"
      "role: node.getAttribute('role') || (node.tagName || '').toLowerCase(),"
      "name: (node.innerText || node.textContent || node.getAttribute('aria-label') || '').trim(),"
      "selector: kelpieBuildSelector(node),"
      "rect: {x: rect.x, y: rect.y, width: rect.width, height: rect.height}"
      "};"
      "}); })()";
  nlohmann::json annotations;
  const BrowserControlResult evaluated = RequireBrowserControl(runtime_).Evaluate(lease, script, &annotations, ControlTimeout(params));
  if (!evaluated.ok) return ControlError(evaluated);
  response["annotations"] = annotations;
  return SuccessResponse(response);
}

}  // namespace kelpie
