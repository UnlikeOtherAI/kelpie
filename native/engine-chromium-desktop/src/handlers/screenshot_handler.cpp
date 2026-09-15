#include "screenshot_handler.h"

#include "kelpie/element_selector_script.h"

namespace kelpie {

ScreenshotHandler::ScreenshotHandler(DesktopHandlerRuntime runtime)
    : runtime_(std::move(runtime)) {}

void ScreenshotHandler::Register(DesktopRouter& router) const {
  router.Register("screenshot",
                  [this](const nlohmann::json& params) { return Screenshot(params, false); });
  router.Register("screenshot-annotated",
                  [this](const nlohmann::json& params) { return Screenshot(params, true); });
}

nlohmann::json ScreenshotHandler::Screenshot(const nlohmann::json& params, bool annotated) const {
  TabLease lease;
  auto result = RequireBrowserControl(runtime_).ResolveTab(OptionalTabId(params), OptionalGeneration(params), &lease, ControlTimeout(params));
  if (!result.ok) return ControlError(result);
  BrowserScreenshot image;
  result = RequireBrowserControl(runtime_).Screenshot(lease, &image, ControlTimeout(params));
  if (!result.ok) return ControlError(result);

  nlohmann::json response = {
      {"image", image.base64_data},
      {"format", image.mime_type == "image/jpeg" ? "jpeg" : "png"},
      {"tab", result.tab ? TabJson(*result.tab) : nlohmann::json::object()},
  };
  if (runtime_.viewport_supplier) {
    const nlohmann::json viewport = runtime_.viewport_supplier();
    response["width"] = viewport.value("width", 0);
    response["height"] = viewport.value("height", 0);
  } else {
    response["width"] = 0;
    response["height"] = 0;
  }

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
