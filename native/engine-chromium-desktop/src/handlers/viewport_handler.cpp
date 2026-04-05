#include "viewport_handler.h"

namespace kelpie {

ViewportHandler::ViewportHandler(DesktopHandlerRuntime runtime) : runtime_(std::move(runtime)) {}

void ViewportHandler::Register(DesktopRouter& router) const {
  router.Register("get-viewport", [this](const nlohmann::json&) { return GetViewport(); });
  router.Register("resize-viewport",
                  [this](const nlohmann::json& params) { return ResizeViewport(params); });
  router.Register("reset-viewport", [this](const nlohmann::json&) { return ResetViewport(); });
}

nlohmann::json ViewportHandler::GetViewport() const {
  if (!runtime_.viewport_supplier) {
    return SuccessResponse(nlohmann::json::object());
  }
  return SuccessResponse(runtime_.viewport_supplier());
}

nlohmann::json ViewportHandler::ResizeViewport(const nlohmann::json& params) const {
  if (!runtime_.viewport_supplier || !runtime_.resize_viewport) {
    return Unsupported("resize-viewport");
  }
  const nlohmann::json original = runtime_.viewport_supplier();
  const int width = IntOrDefault(params, "width", original.value("width", 0));
  const int height = IntOrDefault(params, "height", original.value("height", 0));
  if (!runtime_.resize_viewport(width, height)) {
    return ErrorResponse(ErrorCode::kWebviewError, "Failed to resize viewport");
  }
  return SuccessResponse({{"viewport", runtime_.viewport_supplier()}, {"originalViewport", original}});
}

nlohmann::json ViewportHandler::ResetViewport() const {
  if (!runtime_.viewport_supplier || !runtime_.reset_viewport) {
    return Unsupported("reset-viewport");
  }
  runtime_.reset_viewport();
  return SuccessResponse({{"viewport", runtime_.viewport_supplier()}});
}

}  // namespace kelpie
