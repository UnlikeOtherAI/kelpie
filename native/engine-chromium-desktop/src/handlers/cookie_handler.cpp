#include "cookie_handler.h"

namespace kelpie {

CookieHandler::CookieHandler(DesktopHandlerRuntime runtime) : runtime_(std::move(runtime)) {}

void CookieHandler::Register(DesktopRouter& router) const {
  router.Register("get-cookies", [this](const nlohmann::json&) { return GetCookies(); });
  router.Register("set-cookie",
                  [this](const nlohmann::json& params) { return SetCookie(params); });
  router.Register("delete-cookies",
                  [this](const nlohmann::json& params) { return DeleteCookies(params); });
  router.Register("clear-cookies",
                  [this](const nlohmann::json&) { return DeleteCookies({{"deleteAll", true}}); });
  router.Register("get-storage",
                  [this](const nlohmann::json& params) { return GetStorage(params); });
  router.Register("set-storage",
                  [this](const nlohmann::json& params) { return SetStorage(params); });
  router.Register("clear-storage",
                  [this](const nlohmann::json& params) { return ClearStorage(params); });
}

nlohmann::json CookieHandler::GetCookies() const {
  HandlerContext& context = RequireHandlerContext(runtime_);
  const nlohmann::json result = context.EvaluateJsReturningJson(
      "(() => ({ cookies: document.cookie.split(';').map(item => item.trim()).filter(Boolean).map(item => { const parts = item.split('='); return { name: parts.shift() || '', value: parts.join('=') }; }), count: document.cookie ? document.cookie.split(';').filter(Boolean).length : 0 }))()");
  return SuccessResponse(result);
}

nlohmann::json CookieHandler::SetCookie(const nlohmann::json& params) const {
  try {
    HandlerContext& context = RequireHandlerContext(runtime_);
    const std::string name = RequireString(params, "name");
    const std::string value = RequireString(params, "value");
    std::string cookie = name + "=" + value;
    if (auto it = params.find("path"); it != params.end() && it->is_string()) {
      cookie += "; path=" + it->get<std::string>();
    }
    if (auto it = params.find("domain"); it != params.end() && it->is_string()) {
      cookie += "; domain=" + it->get<std::string>();
    }
    if (BoolOrDefault(params, "secure", false)) {
      cookie += "; secure";
    }
    context.EvaluateJsReturningJson("(() => { document.cookie = " + JsStringLiteral(cookie) + "; return {ok: true}; })()");
    return SuccessResponse();
  } catch (const std::invalid_argument& exception) {
    return InvalidParams(exception.what());
  }
}

nlohmann::json CookieHandler::DeleteCookies(const nlohmann::json& params) const {
  HandlerContext& context = RequireHandlerContext(runtime_);
  const bool delete_all = BoolOrDefault(params, "deleteAll", false);
  std::string script;
  if (delete_all) {
    script =
        "(() => {"
        "const cookies = document.cookie.split(';').map(item => item.trim()).filter(Boolean);"
        "for (const cookie of cookies) { const name = cookie.split('=')[0]; document.cookie = name + '=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/'; }"
        "return {deleted: cookies.length};"
        "})()";
  } else {
    const auto name_it = params.find("name");
    if (name_it == params.end() || !name_it->is_string()) {
      return InvalidParams("name is required unless deleteAll is true");
    }
    script =
        "(() => { document.cookie = " +
        JsStringLiteral(name_it->get<std::string>() +
                        "=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/") +
        "; return {deleted: 1}; })()";
  }
  const nlohmann::json result = context.EvaluateJsReturningJson(script);
  return SuccessResponse({{"deleted", result.value("deleted", 0)}});
}

nlohmann::json CookieHandler::GetStorage(const nlohmann::json& params) const {
  HandlerContext& context = RequireHandlerContext(runtime_);
  const std::string type = params.value("type", std::string("local"));
  const std::string store_name = type == "session" ? "sessionStorage" : "localStorage";
  const auto key_it = params.find("key");
  std::string script =
      "(() => { const store = window." + store_name +
      "; const entries = {}; for (let i = 0; i < store.length; ++i) { const key = store.key(i); entries[key] = store.getItem(key); }"
      "return {type: " + JsStringLiteral(type) + ", entries, count: Object.keys(entries).length}; })()";
  if (key_it != params.end() && key_it->is_string()) {
    script =
        "(() => { const store = window." + store_name + "; const key = " +
        JsStringLiteral(key_it->get<std::string>()) +
        "; const value = store.getItem(key); const entries = value === null ? {} : {[key]: value}; return {type: " +
        JsStringLiteral(type) + ", entries, count: Object.keys(entries).length}; })()";
  }
  return SuccessResponse(context.EvaluateJsReturningJson(script));
}

nlohmann::json CookieHandler::SetStorage(const nlohmann::json& params) const {
  try {
    HandlerContext& context = RequireHandlerContext(runtime_);
    const std::string type = params.value("type", std::string("local"));
    const std::string store_name = type == "session" ? "sessionStorage" : "localStorage";
    const std::string key = RequireString(params, "key");
    const std::string value = RequireString(params, "value");
    context.EvaluateJsReturningJson("(() => { window." + store_name + ".setItem(" +
                                    JsStringLiteral(key) + ", " + JsStringLiteral(value) +
                                    "); return {ok: true}; })()");
    return SuccessResponse();
  } catch (const std::invalid_argument& exception) {
    return InvalidParams(exception.what());
  }
}

nlohmann::json CookieHandler::ClearStorage(const nlohmann::json& params) const {
  HandlerContext& context = RequireHandlerContext(runtime_);
  const std::string type = params.value("type", std::string("local"));
  if (type == "both") {
    context.EvaluateJsReturningJson(
        "(() => { window.localStorage.clear(); window.sessionStorage.clear(); return {cleared: 'both'}; })()");
    return SuccessResponse({{"cleared", "both"}});
  }
  const std::string store_name = type == "session" ? "sessionStorage" : "localStorage";
  context.EvaluateJsReturningJson("(() => { window." + store_name + ".clear(); return {ok: true}; })()");
  return SuccessResponse({{"cleared", type}});
}

}  // namespace kelpie
