#pragma once

#include "handler_support.h"
#include "kelpie/desktop_router.h"

namespace kelpie {

class CookieHandler {
 public:
  explicit CookieHandler(DesktopHandlerRuntime runtime);

  void Register(DesktopRouter& router) const;

 private:
  nlohmann::json GetCookies() const;
  nlohmann::json SetCookie(const nlohmann::json& params) const;
  nlohmann::json DeleteCookies(const nlohmann::json& params) const;
  nlohmann::json GetStorage(const nlohmann::json& params) const;
  nlohmann::json SetStorage(const nlohmann::json& params) const;
  nlohmann::json ClearStorage(const nlohmann::json& params) const;

  DesktopHandlerRuntime runtime_;
};

}  // namespace kelpie
