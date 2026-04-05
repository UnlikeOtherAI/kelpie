#pragma once

#include "handler_support.h"
#include "kelpie/desktop_router.h"

namespace kelpie {

class ViewportHandler {
 public:
  explicit ViewportHandler(DesktopHandlerRuntime runtime);

  void Register(DesktopRouter& router) const;

 private:
  nlohmann::json GetViewport() const;
  nlohmann::json ResizeViewport(const nlohmann::json& params) const;
  nlohmann::json ResetViewport() const;

  DesktopHandlerRuntime runtime_;
};

}  // namespace kelpie
