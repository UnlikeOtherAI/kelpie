#include "dom_handler.h"

namespace kelpie {

DomHandler::DomHandler(DesktopHandlerRuntime runtime) : runtime_(std::move(runtime)) {}

void DomHandler::Register(DesktopRouter& router) const {
  router.Register("query-selector",
                  [this](const nlohmann::json& params) { return QuerySelector(params, false); });
  router.Register("query-selector-all",
                  [this](const nlohmann::json& params) { return QuerySelector(params, true); });
  router.Register("get-element-text",
                  [this](const nlohmann::json& params) { return GetElementText(params); });
  router.Register("get-attributes",
                  [this](const nlohmann::json& params) { return GetAttributes(params); });
  router.Register("get-dom", [this](const nlohmann::json& params) { return GetDom(params); });
}

nlohmann::json DomHandler::QuerySelector(const nlohmann::json& params, bool all) const {
  try {
    HandlerContext& context = RequireHandlerContext(runtime_);
    const std::string selector = RequireString(params, "selector");
    const std::string script =
        "(() => {"
        "const nodes = Array.from(document.querySelectorAll(" + JsStringLiteral(selector) + "));"
        "const mapped = nodes.map(node => ({"
        "  tag: (node.tagName || '').toLowerCase(),"
        "  id: node.id || undefined,"
        "  text: (node.textContent || '').trim(),"
        "  classes: Array.from(node.classList || []),"
        "  rect: (() => { const r = node.getBoundingClientRect(); return {x: r.x, y: r.y, width: r.width, height: r.height}; })(),"
        "  visible: !!(node.offsetWidth || node.offsetHeight || node.getClientRects().length)"
        "}));"
        "return {count: mapped.length, elements: mapped};"
        "})()";
    const nlohmann::json result = context.EvaluateJsReturningJson(script);
    const nlohmann::json elements = result.value("elements", nlohmann::json::array());
    if (!all) {
      return SuccessResponse({
          {"found", !elements.empty()},
          {"element", elements.empty() ? nlohmann::json() : elements.front()},
      });
    }
    return SuccessResponse({
        {"count", result.value("count", 0)},
        {"elements", elements},
    });
  } catch (const std::invalid_argument& exception) {
    return InvalidParams(exception.what());
  }
}

nlohmann::json DomHandler::GetElementText(const nlohmann::json& params) const {
  try {
    HandlerContext& context = RequireHandlerContext(runtime_);
    const std::string selector = RequireString(params, "selector");
    const std::string script =
        "(() => { const node = document.querySelector(" + JsStringLiteral(selector) +
        "); return node ? {found: true, text: (node.textContent || '').trim()} : {found: false}; })()";
    const nlohmann::json result = context.EvaluateJsReturningJson(script);
    if (!result.value("found", false)) {
      return ErrorResponse(ErrorCode::kElementNotFound,
                           "No element matching selector '" + selector + "'");
    }
    return SuccessResponse({{"text", result.value("text", "")}});
  } catch (const std::invalid_argument& exception) {
    return InvalidParams(exception.what());
  }
}

nlohmann::json DomHandler::GetAttributes(const nlohmann::json& params) const {
  try {
    HandlerContext& context = RequireHandlerContext(runtime_);
    const std::string selector = RequireString(params, "selector");
    const std::string script =
        "(() => {"
        "const node = document.querySelector(" + JsStringLiteral(selector) + ");"
        "if (!node) { return {found: false}; }"
        "const attrs = Array.from(node.attributes || []).reduce((acc, attr) => { acc[attr.name] = attr.value; return acc; }, {});"
        "return {found: true, attributes: attrs};"
        "})()";
    const nlohmann::json result = context.EvaluateJsReturningJson(script);
    if (!result.value("found", false)) {
      return ErrorResponse(ErrorCode::kElementNotFound,
                           "No element matching selector '" + selector + "'");
    }
    return SuccessResponse({{"attributes", result.value("attributes", nlohmann::json::object())}});
  } catch (const std::invalid_argument& exception) {
    return InvalidParams(exception.what());
  }
}

nlohmann::json DomHandler::GetDom(const nlohmann::json& params) const {
  HandlerContext& context = RequireHandlerContext(runtime_);
  const auto selector_it = params.find("selector");
  const std::string selector =
      selector_it != params.end() && selector_it->is_string() ? selector_it->get<std::string>() : "html";
  const std::string script =
      "(() => {"
      "const node = document.querySelector(" + JsStringLiteral(selector) + ");"
      "if (!node) { return {found: false}; }"
      "return {found: true, html: node.outerHTML || '', nodeCount: node.querySelectorAll('*').length + 1};"
      "})()";
  const nlohmann::json result = context.EvaluateJsReturningJson(script);
  if (!result.value("found", false)) {
    return ErrorResponse(ErrorCode::kElementNotFound,
                         "No element matching selector '" + selector + "'");
  }
  return SuccessResponse({
      {"html", result.value("html", "")},
      {"nodeCount", result.value("nodeCount", 0)},
  });
}

}  // namespace kelpie
