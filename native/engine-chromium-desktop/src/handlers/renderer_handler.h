#pragma once

#include "handler_support.h"
#include "kelpie/desktop_router.h"

namespace kelpie {

class RendererHandler {
 public:
  explicit RendererHandler(DesktopHandlerRuntime runtime);

  void Register(DesktopRouter& router) const;

 private:
  nlohmann::json GetRenderer() const;
  nlohmann::json SetRenderer() const;

  DesktopHandlerRuntime runtime_;
};

}  // namespace kelpie
