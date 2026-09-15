#include "shell_handler.h"
namespace kelpie {
void ShellHandler::Register(DesktopRouter& router) const {
  router.Register("set-home", [this](const nlohmann::json& p) { return SetHome(p); }, static_cast<bool>(runtime_.set_home));
  router.Register("get-home", [this](const nlohmann::json&) { return GetHome(); }, static_cast<bool>(runtime_.get_home));
  router.Register("toast", [this](const nlohmann::json& p) { return Toast(p); }, static_cast<bool>(runtime_.show_native_toast));
  router.Register("set-fullscreen", [this](const nlohmann::json& p) { return SetFullscreen(p); }, static_cast<bool>(runtime_.set_native_fullscreen));
  router.Register("get-fullscreen", [this](const nlohmann::json&) { return GetFullscreen(); }, static_cast<bool>(runtime_.get_native_fullscreen));
  router.Register("close-browser", [this](const nlohmann::json&) { return CloseBrowser(); }, static_cast<bool>(runtime_.request_shutdown));
}
nlohmann::json ShellHandler::SetHome(const nlohmann::json& params) const {
  try { if (!runtime_.set_home) return Unsupported("set-home"); const std::string url=RequireString(params,"url"); const auto result=runtime_.set_home(url); return result.ok ? SuccessResponse({{"url",url}}) : ControlError(result); }
  catch (const std::invalid_argument& e) { return InvalidParams(e.what()); }
}
nlohmann::json ShellHandler::GetHome() const {
  if (!runtime_.get_home) return Unsupported("get-home"); std::string url; const auto result=runtime_.get_home(&url); return result.ok ? SuccessResponse({{"url",url}}) : ControlError(result);
}
nlohmann::json ShellHandler::Toast(const nlohmann::json& params) const {
  try { if (!runtime_.show_native_toast) return Unsupported("toast"); const auto result=runtime_.show_native_toast(RequireString(params,"message")); return result.ok ? SuccessResponse() : ControlError(result); }
  catch (const std::invalid_argument& e) { return InvalidParams(e.what()); }
}
nlohmann::json ShellHandler::SetFullscreen(const nlohmann::json& params) const {
  if (!runtime_.set_native_fullscreen) return Unsupported("set-fullscreen"); const auto it=params.find("enabled"); if(it==params.end()||!it->is_boolean()) return InvalidParams("enabled must be a boolean"); const auto result=runtime_.set_native_fullscreen(it->get<bool>()); return result.ok ? SuccessResponse({{"fullscreen",it->get<bool>()}}) : ControlError(result);
}
nlohmann::json ShellHandler::GetFullscreen() const {
  if (!runtime_.get_native_fullscreen) return Unsupported("get-fullscreen"); bool enabled=false; const auto result=runtime_.get_native_fullscreen(&enabled); return result.ok ? SuccessResponse({{"fullscreen",enabled}}) : ControlError(result);
}
nlohmann::json ShellHandler::CloseBrowser() const {
  if (!runtime_.request_shutdown) return Unsupported("close-browser"); const auto result=runtime_.request_shutdown(); return result.ok ? SuccessResponse({{"accepted",true}}) : ControlError(result);
}
}  // namespace kelpie
