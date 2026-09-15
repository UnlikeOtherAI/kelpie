#include "cookie_handler.h"

namespace kelpie {
namespace {

std::string StorageType(const nlohmann::json& params, bool allow_both) {
  const auto type = params.find("type");
  if (type == params.end()) return "local";
  if (!type->is_string()) throw std::invalid_argument("type must be a string");
  const std::string value = type->get<std::string>();
  if (value != "local" && value != "session" && (!allow_both || value != "both")) {
    throw std::invalid_argument(allow_both ? "type must be local, session, or both" : "type must be local or session");
  }
  return value;
}

BrowserControlResult Resolve(const DesktopHandlerRuntime& runtime, const nlohmann::json& params,
                             TabLease* lease) {
  return RequireBrowserControl(runtime).ResolveTab(OptionalTabId(params), OptionalGeneration(params),
                                                    lease, ControlTimeout(params));
}

nlohmann::json WithTab(const BrowserControlResult& result, nlohmann::json body) {
  if (result.tab) body["tab"] = TabJson(*result.tab);
  return SuccessResponse(std::move(body));
}

}  // namespace

CookieHandler::CookieHandler(DesktopHandlerRuntime runtime) : runtime_(std::move(runtime)) {}

void CookieHandler::Register(DesktopRouter& router) const {
  router.Register("get-cookies", [this](const nlohmann::json& p) { return GetCookies(p); });
  router.Register("set-cookie", [this](const nlohmann::json& p) { return SetCookie(p); });
  router.Register("delete-cookies", [this](const nlohmann::json& p) { return DeleteCookies(p); });
  router.Register("clear-cookies", [this](const nlohmann::json& p) {
    nlohmann::json request = p; request["deleteAll"] = true; return DeleteCookies(request);
  });
  router.Register("get-storage", [this](const nlohmann::json& p) { return GetStorage(p); });
  router.Register("set-storage", [this](const nlohmann::json& p) { return SetStorage(p); });
  router.Register("clear-storage", [this](const nlohmann::json& p) { return ClearStorage(p); });
}

nlohmann::json CookieHandler::GetCookies(const nlohmann::json& params) const {
  try {
    TabLease lease; BrowserControlResult result = Resolve(runtime_, params, &lease);
    if (!result.ok) return ControlError(result);
    nlohmann::json cookies;
    result = RequireBrowserControl(runtime_).GetCookies(lease, params, &cookies, ControlTimeout(params));
    if (!result.ok) return ControlError(result);
    return WithTab(result, {{"cookies", cookies}});
  } catch (const std::invalid_argument& e) { return InvalidParams(e.what()); }
}

nlohmann::json CookieHandler::SetCookie(const nlohmann::json& params) const {
  try {
    RequireString(params, "name"); RequireString(params, "value");
    TabLease lease; BrowserControlResult result = Resolve(runtime_, params, &lease);
    if (!result.ok) return ControlError(result);
    nlohmann::json output;
    result = RequireBrowserControl(runtime_).SetCookies(lease, params, &output, ControlTimeout(params));
    if (!result.ok) return ControlError(result);
    return WithTab(result, {{"result", output}});
  } catch (const std::invalid_argument& e) { return InvalidParams(e.what()); }
}

nlohmann::json CookieHandler::DeleteCookies(const nlohmann::json& params) const {
  try {
    const bool all = BoolOrDefault(params, "deleteAll", false);
    if (!all) RequireString(params, "name");
    TabLease lease; BrowserControlResult result = Resolve(runtime_, params, &lease);
    if (!result.ok) return ControlError(result);
    nlohmann::json output;
    result = RequireBrowserControl(runtime_).DeleteCookies(lease, params, &output, ControlTimeout(params));
    if (!result.ok) return ControlError(result);
    return WithTab(result, {{"result", output}});
  } catch (const std::invalid_argument& e) { return InvalidParams(e.what()); }
}

nlohmann::json CookieHandler::GetStorage(const nlohmann::json& params) const {
  try {
    const std::string type = StorageType(params, false);
    const std::string store = type == "session" ? "sessionStorage" : "localStorage";
    std::string script = "(() => { const s=window." + store + "; const e={}; for(let i=0;i<s.length;i++){const k=s.key(i);e[k]=s.getItem(k);} return {type:"" + type + "",entries:e,count:Object.keys(e).length}; })()";
    if (params.contains("key")) {
      const std::string key = RequireString(params, "key");
      script = "(() => { const s=window." + store + "; const k=" + JsStringLiteral(key) + "; const v=s.getItem(k); return {type:"" + type + "",entries:v===null?{}:{[k]:v},count:v===null?0:1}; })()";
    }
    nlohmann::json value; const BrowserControlResult result = EvaluateForTab(runtime_, params, script, &value);
    return result.ok ? SuccessResponse(value) : ControlError(result);
  } catch (const std::invalid_argument& e) { return InvalidParams(e.what()); }
}

nlohmann::json CookieHandler::SetStorage(const nlohmann::json& params) const {
  try {
    const std::string type = StorageType(params, false);
    const std::string key = RequireString(params, "key"), value = RequireString(params, "value");
    const std::string store = type == "session" ? "sessionStorage" : "localStorage";
    nlohmann::json output; const BrowserControlResult result = EvaluateForTab(runtime_, params,
        "(() => { window." + store + ".setItem(" + JsStringLiteral(key) + "," + JsStringLiteral(value) + "); return {type:" + JsStringLiteral(type) + ",key:" + JsStringLiteral(key) + "}; })()", &output);
    return result.ok ? SuccessResponse(output) : ControlError(result);
  } catch (const std::invalid_argument& e) { return InvalidParams(e.what()); }
}

nlohmann::json CookieHandler::ClearStorage(const nlohmann::json& params) const {
  try {
    const std::string type = StorageType(params, true);
    const std::string script = type == "both" ? "(() => { localStorage.clear(); sessionStorage.clear(); return {cleared:'both'}; })()" :
        "(() => { window." + std::string(type == "session" ? "sessionStorage" : "localStorage") + ".clear(); return {cleared:" + JsStringLiteral(type) + "}; })()";
    nlohmann::json output; const BrowserControlResult result = EvaluateForTab(runtime_, params, script, &output);
    return result.ok ? SuccessResponse(output) : ControlError(result);
  } catch (const std::invalid_argument& e) { return InvalidParams(e.what()); }
}

}  // namespace kelpie
