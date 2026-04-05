#include "browser_mgmt_handler.h"

namespace kelpie {

BrowserManagementHandler::BrowserManagementHandler(DesktopHandlerRuntime runtime)
    : runtime_(std::move(runtime)) {}

void BrowserManagementHandler::Register(DesktopRouter& router) const {
  router.Register("get-tabs", [this](const nlohmann::json&) { return GetTabs(); });
  router.Register("new-tab", [this](const nlohmann::json& params) { return NewTab(params); });
  router.Register("switch-tab", [](const nlohmann::json&) { return Unsupported("switch-tab"); });
  router.Register("close-tab", [](const nlohmann::json&) { return Unsupported("close-tab"); });
}

nlohmann::json BrowserManagementHandler::GetTabs() const {
  HandlerContext& context = RequireHandlerContext(runtime_);
  const nlohmann::json tab = {
      {"id", 0},
      {"url", context.Renderer()->CurrentUrl()},
      {"title", context.Renderer()->CurrentTitle()},
      {"active", true},
  };
  return SuccessResponse({{"tabs", nlohmann::json::array({tab})}, {"count", 1}, {"activeTab", 0}});
}

nlohmann::json BrowserManagementHandler::NewTab(const nlohmann::json& params) const {
  HandlerContext& context = RequireHandlerContext(runtime_);
  const auto url_it = params.find("url");
  if (url_it != params.end() && url_it->is_string() && !url_it->get<std::string>().empty()) {
    context.Renderer()->LoadUrl(url_it->get<std::string>());
  }
  return SuccessResponse({
      {"tab", {{"id", 0},
                {"url", context.Renderer()->CurrentUrl()},
                {"title", context.Renderer()->CurrentTitle()}}},
      {"tabCount", 1},
  });
}

}  // namespace kelpie
