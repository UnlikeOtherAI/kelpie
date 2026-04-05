#include "screenshot_handler.h"

namespace kelpie {

ScreenshotHandler::ScreenshotHandler(DesktopHandlerRuntime runtime)
    : runtime_(std::move(runtime)) {}

void ScreenshotHandler::Register(DesktopRouter& router) const {
  router.Register("screenshot",
                  [this](const nlohmann::json& params) { return Screenshot(params, false); });
  router.Register("screenshot-annotated",
                  [this](const nlohmann::json& params) { return Screenshot(params, true); });
}

nlohmann::json ScreenshotHandler::Screenshot(const nlohmann::json&, bool annotated) const {
  HandlerContext& context = RequireHandlerContext(runtime_);
  const auto image = context.Renderer()->TakeSnapshot();
  if (image.empty()) {
    return ErrorResponse(ErrorCode::kWebviewError, "No snapshot is available");
  }

  nlohmann::json response = {
      {"image", Base64Encode(image)},
      {"format", "png"},
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
      "(() => Array.from(document.querySelectorAll('a,button,input,select,textarea,[role=button]')).map((node, index) => {"
      "const rect = node.getBoundingClientRect();"
      "return {"
      "index: index + 1,"
      "role: node.getAttribute('role') || (node.tagName || '').toLowerCase(),"
      "name: (node.innerText || node.textContent || node.getAttribute('aria-label') || '').trim(),"
      "selector: (node.id ? ('#' + node.id) : (node.tagName || '').toLowerCase()),"
      "rect: {x: rect.x, y: rect.y, width: rect.width, height: rect.height}"
      "};"
      "}));";
  response["annotations"] = RequireHandlerContext(runtime_).EvaluateJsReturningJson(script);
  return SuccessResponse(response);
}

}  // namespace kelpie
