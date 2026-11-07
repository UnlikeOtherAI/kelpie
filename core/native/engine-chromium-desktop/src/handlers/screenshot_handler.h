#pragma once

#include "handler_support.h"
#include "kelpie/desktop_router.h"

namespace kelpie {

class ScreenshotHandler {
 public:
  explicit ScreenshotHandler(DesktopHandlerRuntime runtime);

  void Register(DesktopRouter& router) const;

 private:
  nlohmann::json Screenshot(const nlohmann::json& params, bool annotated) const;

  DesktopHandlerRuntime runtime_;
};

}  // namespace kelpie
