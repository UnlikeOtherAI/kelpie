#pragma once
#include <memory>
#include <nlohmann/json.hpp>
#include "kelpie/desktop_router.h"
namespace kelpie {
class DesktopBrowserControl;
class HandlerContext;
// Reuse the real desktop tab/input handlers in platform shells such as Linux.
class DesktopCoreBrowser {
 public:
  DesktopCoreBrowser(DesktopBrowserControl& control, HandlerContext& context);
  ~DesktopCoreBrowser();
  DesktopRouter& router();
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
nlohmann::json EvaluateBrowserFixed(DesktopBrowserControl& control, const nlohmann::json& params);
}
