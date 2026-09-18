#pragma once
#include "handler_support.h"
#include "kelpie/desktop_router.h"
namespace kelpie {
class InspectionHandler {
 public:
  explicit InspectionHandler(DesktopHandlerRuntime runtime) : runtime_(std::move(runtime)) {}
  void Register(DesktopRouter& router) const;
 private:
  nlohmann::json Find(const nlohmann::json& params, const char* selector, const char* label) const;
  nlohmann::json Evaluate(const nlohmann::json& params, const std::string& script) const;
  nlohmann::json VisibleElements(const nlohmann::json& params) const;
  nlohmann::json PageText(const nlohmann::json& params) const;
  nlohmann::json FormState(const nlohmann::json& params) const;
  nlohmann::json AccessibilityTree(const nlohmann::json& params) const;
  DesktopHandlerRuntime runtime_;
};
}  // namespace kelpie
