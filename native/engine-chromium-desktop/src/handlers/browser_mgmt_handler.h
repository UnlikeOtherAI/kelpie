#pragma once

#include "handler_support.h"
#include "kelpie/desktop_router.h"

namespace kelpie {

class BrowserManagementHandler {
 public:
  explicit BrowserManagementHandler(DesktopHandlerRuntime runtime);

  void Register(DesktopRouter& router) const;

 private:
  nlohmann::json GetTabs() const;
  nlohmann::json NewTab(const nlohmann::json& params) const;

  DesktopHandlerRuntime runtime_;
};

}  // namespace kelpie
