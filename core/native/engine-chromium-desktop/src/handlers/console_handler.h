#pragma once

#include "handler_support.h"
#include "kelpie/desktop_router.h"

namespace kelpie {

class ConsoleHandler {
 public:
  explicit ConsoleHandler(DesktopHandlerRuntime runtime);

  void Register(DesktopRouter& router) const;

 private:
  nlohmann::json GetConsoleMessages(const nlohmann::json& params) const;
  nlohmann::json GetJsErrors() const;
  nlohmann::json ClearConsole() const;

  DesktopHandlerRuntime runtime_;
};

}  // namespace kelpie
