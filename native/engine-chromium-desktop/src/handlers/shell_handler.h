#pragma once
#include "handler_support.h"
#include "kelpie/desktop_router.h"
namespace kelpie {
class ShellHandler {
 public:
  explicit ShellHandler(DesktopHandlerRuntime runtime) : runtime_(std::move(runtime)) {}
  void Register(DesktopRouter& router) const;
 private:
  nlohmann::json SetHome(const nlohmann::json& params) const;
  nlohmann::json GetHome() const;
  nlohmann::json Toast(const nlohmann::json& params) const;
  nlohmann::json SetFullscreen(const nlohmann::json& params) const;
  nlohmann::json GetFullscreen() const;
  nlohmann::json CloseBrowser() const;
  DesktopHandlerRuntime runtime_;
};
}  // namespace kelpie
