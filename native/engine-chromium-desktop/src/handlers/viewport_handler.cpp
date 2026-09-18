#include "viewport_handler.h"

namespace kelpie {

ViewportHandler::ViewportHandler(DesktopHandlerRuntime runtime) : runtime_(std::move(runtime)) {}

void ViewportHandler::Register(DesktopRouter& router) const {
  router.Register("get-viewport", [this](const nlohmann::json& p) { return GetViewport(p); });
  router.Register("resize-viewport",
                  [this](const nlohmann::json& params) { return ResizeViewport(params); });
  router.Register("reset-viewport", [this](const nlohmann::json& p) { return ResetViewport(p); });
}

nlohmann::json ViewportHandler::GetViewport(const nlohmann::json& params) const {
  if (const auto invalid = RejectBrowserWideTab(params)) return *invalid;
  if (!runtime_.viewport_supplier) {
    return Unsupported("get-viewport");
  }
  return SuccessResponse(runtime_.viewport_supplier());
}

nlohmann::json ViewportHandler::ResizeViewport(const nlohmann::json& params) const {
  if (const auto invalid = RejectBrowserWideTab(params)) return *invalid;
  if (!runtime_.viewport_supplier || !runtime_.resize_viewport) {
    return Unsupported("resize-viewport");
  }
  try {
  const nlohmann::json original = runtime_.viewport_supplier();
  const int width = RequireBoundedInteger(params, "width", 1, 16384);
  const int height = RequireBoundedInteger(params, "height", 1, 16384);
  if (!runtime_.resize_viewport(width, height)) {
    return ErrorResponse(ErrorCode::kWebviewError, "Failed to resize viewport");
  }
  return SuccessResponse({{"viewport", runtime_.viewport_supplier()}, {"originalViewport", original}});
  } catch (const std::invalid_argument& error) { return InvalidParams(error.what()); }
}

nlohmann::json ViewportHandler::ResetViewport(const nlohmann::json& params) const {
  if (const auto invalid = RejectBrowserWideTab(params)) return *invalid;
  if (!runtime_.viewport_supplier || !runtime_.reset_viewport) {
    return Unsupported("reset-viewport");
  }
  if (!runtime_.reset_viewport()) {
    return ErrorResponse(ErrorCode::kWebviewError, "Failed to reset viewport");
  }
  return SuccessResponse({{"viewport", runtime_.viewport_supplier()}});
}

}  // namespace kelpie
