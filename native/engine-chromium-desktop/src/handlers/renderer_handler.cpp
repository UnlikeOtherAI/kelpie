#include "renderer_handler.h"

namespace kelpie {

RendererHandler::RendererHandler(DesktopHandlerRuntime runtime) : runtime_(std::move(runtime)) {}

void RendererHandler::Register(DesktopRouter& router) const {
  router.Register("get-renderer", [this](const nlohmann::json&) { return GetRenderer(); });
  router.Register("set-renderer", [this](const nlohmann::json&) { return SetRenderer(); });
}

nlohmann::json RendererHandler::GetRenderer() const {
  if (runtime_.renderer_supplier) {
    return runtime_.renderer_supplier();
  }
  return SuccessResponse({{"current", runtime_.engine_name}, {"available", {"chromium"}}});
}

nlohmann::json RendererHandler::SetRenderer() const {
  return Unsupported("set-renderer");
}

}  // namespace kelpie
