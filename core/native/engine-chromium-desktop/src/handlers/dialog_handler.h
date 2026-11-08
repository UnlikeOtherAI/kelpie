#pragma once
#include "handler_support.h"
#include "kelpie/desktop_router.h"
namespace kelpie {
class DialogHandler {
 public:
  explicit DialogHandler(DesktopHandlerRuntime runtime) : runtime_(std::move(runtime)) {}
  void Register(DesktopRouter& router) const;
 private:
  nlohmann::json Get(const nlohmann::json& params) const;
  nlohmann::json Handle(const nlohmann::json& params) const;
  DesktopHandlerRuntime runtime_;
};
}  // namespace kelpie
