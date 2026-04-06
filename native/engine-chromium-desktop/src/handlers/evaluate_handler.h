#pragma once

#include "handler_support.h"
#include "kelpie/desktop_router.h"

namespace kelpie {

class EvaluateHandler {
 public:
  explicit EvaluateHandler(DesktopHandlerRuntime runtime);

  void Register(DesktopRouter& router) const;

 private:
  nlohmann::json Evaluate(const nlohmann::json& params) const;
  nlohmann::json WaitForElement(const nlohmann::json& params) const;
  nlohmann::json WaitForNavigation(const nlohmann::json& params) const;

  DesktopHandlerRuntime runtime_;
};

}  // namespace kelpie
