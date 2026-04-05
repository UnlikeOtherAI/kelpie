#pragma once

#include "handler_support.h"
#include "kelpie/desktop_router.h"

namespace kelpie {

class ScrollHandler {
 public:
  explicit ScrollHandler(DesktopHandlerRuntime runtime);

  void Register(DesktopRouter& router) const;

 private:
  nlohmann::json Scroll(const nlohmann::json& params) const;
  nlohmann::json ScrollTo(const std::string& expression) const;

  DesktopHandlerRuntime runtime_;
};

}  // namespace kelpie
