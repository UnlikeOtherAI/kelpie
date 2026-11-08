#pragma once

#include "handler_support.h"
#include "kelpie/desktop_router.h"

namespace kelpie {

class HistoryHandler {
 public:
  explicit HistoryHandler(DesktopHandlerRuntime runtime);

  void Register(DesktopRouter& router) const;

 private:
  nlohmann::json List(const nlohmann::json& params) const;
  nlohmann::json Clear() const;

  DesktopHandlerRuntime runtime_;
};

}  // namespace kelpie
