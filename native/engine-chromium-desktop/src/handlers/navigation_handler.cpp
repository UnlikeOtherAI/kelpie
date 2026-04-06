#include "navigation_handler.h"

#include <chrono>
#include <thread>

namespace kelpie {

NavigationHandler::NavigationHandler(DesktopHandlerRuntime runtime)
    : runtime_(std::move(runtime)) {}

void NavigationHandler::Register(DesktopRouter& router) const {
  router.Register("navigate", [this](const nlohmann::json& params) { return Navigate(params); });
  router.Register("back", [this](const nlohmann::json& params) { return Back(params); });
  router.Register("forward", [this](const nlohmann::json& params) { return Forward(params); });
  router.Register("reload", [this](const nlohmann::json& params) { return Reload(params); });
  router.Register("get-current-url",
                  [this](const nlohmann::json&) { return GetCurrentUrl(); });
}

nlohmann::json NavigationHandler::Navigate(const nlohmann::json& params) const {
  try {
    const std::string url = RequireString(params, "url");
    const std::int64_t started = NowMillis();
    HandlerContext& context = RequireHandlerContext(runtime_);
    context.Renderer()->LoadUrl(url);

    const int timeout_ms = 10000;
    const int poll_ms = 100;
    while (context.Renderer()->IsLoading() && (NowMillis() - started) < timeout_ms) {
      std::this_thread::sleep_for(std::chrono::milliseconds(poll_ms));
    }

    const std::string current_url = context.Renderer()->CurrentUrl();
    const std::string title = context.Renderer()->CurrentTitle();
    if (runtime_.history_store != nullptr) {
      runtime_.history_store->Record(current_url.empty() ? url : current_url, title);
    }
    return SuccessResponse({
        {"url", current_url.empty() ? url : current_url},
        {"title", title},
        {"loadTime", static_cast<int>(NowMillis() - started)},
    });
  } catch (const std::invalid_argument& exception) {
    return InvalidParams(exception.what());
  }
}

nlohmann::json NavigationHandler::Back(const nlohmann::json&) const {
  HandlerContext& context = RequireHandlerContext(runtime_);
  context.Renderer()->GoBack();
  return SuccessResponse({
      {"url", context.Renderer()->CurrentUrl()},
      {"title", context.Renderer()->CurrentTitle()},
  });
}

nlohmann::json NavigationHandler::Forward(const nlohmann::json&) const {
  HandlerContext& context = RequireHandlerContext(runtime_);
  context.Renderer()->GoForward();
  return SuccessResponse({
      {"url", context.Renderer()->CurrentUrl()},
      {"title", context.Renderer()->CurrentTitle()},
  });
}

nlohmann::json NavigationHandler::Reload(const nlohmann::json&) const {
  const std::int64_t started = NowMillis();
  HandlerContext& context = RequireHandlerContext(runtime_);
  context.Renderer()->Reload();
  return SuccessResponse({
      {"url", context.Renderer()->CurrentUrl()},
      {"loadTime", static_cast<int>(NowMillis() - started)},
  });
}

nlohmann::json NavigationHandler::GetCurrentUrl() const {
  HandlerContext& context = RequireHandlerContext(runtime_);
  return {
      {"url", context.Renderer()->CurrentUrl()},
      {"title", context.Renderer()->CurrentTitle()},
  };
}

}  // namespace kelpie
