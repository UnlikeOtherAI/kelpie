#pragma once

#include "handler_support.h"
#include "kelpie/desktop_router.h"

namespace kelpie {

class NetworkHandler {
 public:
  explicit NetworkHandler(DesktopHandlerRuntime runtime);

  void Register(DesktopRouter& router) const;

 private:
  nlohmann::json GetNetworkLog(const nlohmann::json& params) const;
  nlohmann::json ClearNetworkLog() const;

  DesktopHandlerRuntime runtime_;
};

}  // namespace kelpie
