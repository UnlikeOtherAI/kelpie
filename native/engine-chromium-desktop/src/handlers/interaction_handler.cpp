#include "interaction_handler.h"

namespace kelpie {
namespace {

const char* kClickScript = R"JS(
(() => {
  const selector = SELECTOR;
  const element = document.querySelector(selector);
  if (!element) {
    return {found: false};
  }
  element.click();
  return {
    found: true,
    tag: (element.tagName || "").toLowerCase(),
    text: (element.innerText || element.textContent || "").trim()
  };
})()
)JS";

}  // namespace

InteractionHandler::InteractionHandler(DesktopHandlerRuntime runtime)
    : runtime_(std::move(runtime)) {}

void InteractionHandler::Register(DesktopRouter& router) const {
  router.Register("click", [this](const nlohmann::json& params) { return Click(params); });
  router.Register("fill", [this](const nlohmann::json& params) { return Fill(params); });
  router.Register("type", [this](const nlohmann::json& params) { return Type(params); });
  router.Register("select-option",
                  [this](const nlohmann::json& params) { return SelectOption(params); });
  router.Register("check", [this](const nlohmann::json& params) { return Check(params, true); });
  router.Register("uncheck",
                  [this](const nlohmann::json& params) { return Check(params, false); });
}

nlohmann::json InteractionHandler::Click(const nlohmann::json& params) const {
  try {
    HandlerContext& context = RequireHandlerContext(runtime_);
    std::string script = kClickScript;
    const std::string selector = RequireString(params, "selector");
    const auto position = script.find("SELECTOR");
    script.replace(position, 8, JsStringLiteral(selector));

    const nlohmann::json result = context.EvaluateJsReturningJson(script);
    if (!result.value("found", false)) {
      return ErrorResponse(ErrorCode::kElementNotFound,
                           "No element matching selector '" + selector + "'");
    }
    return SuccessResponse({
        {"element", {{"tag", result.value("tag", "")}, {"text", result.value("text", "")}}},
    });
  } catch (const std::invalid_argument& exception) {
    return InvalidParams(exception.what());
  }
}

nlohmann::json InteractionHandler::Fill(const nlohmann::json& params) const {
  try {
    HandlerContext& context = RequireHandlerContext(runtime_);
    const std::string selector = RequireString(params, "selector");
    const std::string value = RequireString(params, "value");
    const std::string script =
        "(() => {"
        "const element = document.querySelector(" + JsStringLiteral(selector) + ");"
        "if (!element) { return {found: false}; }"
        "element.focus(); element.value = " + JsStringLiteral(value) + ";"
        "element.dispatchEvent(new Event('input', {bubbles: true}));"
        "element.dispatchEvent(new Event('change', {bubbles: true}));"
        "return {found: true};"
        "})()";
    const nlohmann::json result = context.EvaluateJsReturningJson(script);
    if (!result.value("found", false)) {
      return ErrorResponse(ErrorCode::kElementNotFound,
                           "No element matching selector '" + selector + "'");
    }
    return SuccessResponse({{"selector", selector}, {"value", value}});
  } catch (const std::invalid_argument& exception) {
    return InvalidParams(exception.what());
  }
}

nlohmann::json InteractionHandler::Type(const nlohmann::json& params) const {
  try {
    HandlerContext& context = RequireHandlerContext(runtime_);
    const std::string text = RequireString(params, "text");
    const auto selector_it = params.find("selector");
    const std::string selector =
        selector_it != params.end() && selector_it->is_string() ? selector_it->get<std::string>() : "";
    std::string script = "(() => { let element = document.activeElement;";
    if (!selector.empty()) {
      script += "element = document.querySelector(" + JsStringLiteral(selector) + ");";
    }
    script +=
        "if (!element) { return {found: false}; }"
        "element.focus();"
        "const text = " + JsStringLiteral(text) + ";"
        "for (const ch of text) {"
        "  const next = (element.value || '') + ch;"
        "  element.value = next;"
        "}"
        "element.dispatchEvent(new Event('input', {bubbles: true}));"
        "return {found: true};"
        "})()";
    const nlohmann::json result = context.EvaluateJsReturningJson(script);
    if (!result.value("found", false)) {
      return ErrorResponse(ErrorCode::kElementNotFound, "No active or matching input element");
    }
    return SuccessResponse({{"typed", text}});
  } catch (const std::invalid_argument& exception) {
    return InvalidParams(exception.what());
  }
}

nlohmann::json InteractionHandler::SelectOption(const nlohmann::json& params) const {
  try {
    HandlerContext& context = RequireHandlerContext(runtime_);
    const std::string selector = RequireString(params, "selector");
    const std::string value = RequireString(params, "value");
    const std::string script =
        "(() => {"
        "const select = document.querySelector(" + JsStringLiteral(selector) + ");"
        "if (!select) { return {found: false}; }"
        "const option = Array.from(select.options || []).find(item => item.value === " +
        JsStringLiteral(value) + ");"
        "if (!option) { return {found: true, selected: false}; }"
        "select.value = option.value;"
        "select.dispatchEvent(new Event('change', {bubbles: true}));"
        "return {found: true, selected: true, value: option.value, text: option.text || ''};"
        "})()";
    const nlohmann::json result = context.EvaluateJsReturningJson(script);
    if (!result.value("found", false)) {
      return ErrorResponse(ErrorCode::kElementNotFound,
                           "No element matching selector '" + selector + "'");
    }
    if (!result.value("selected", false)) {
      return ErrorResponse(ErrorCode::kInvalidParams,
                           "No option with value '" + value + "'");
    }
    return SuccessResponse({
        {"selected", {{"value", result.value("value", value)},
                       {"text", result.value("text", "")}}},
    });
  } catch (const std::invalid_argument& exception) {
    return InvalidParams(exception.what());
  }
}

nlohmann::json InteractionHandler::Check(const nlohmann::json& params, bool checked) const {
  try {
    HandlerContext& context = RequireHandlerContext(runtime_);
    const std::string selector = RequireString(params, "selector");
    const std::string script =
        "(() => {"
        "const element = document.querySelector(" + JsStringLiteral(selector) + ");"
        "if (!element) { return {found: false}; }"
        "element.checked = " + std::string(checked ? "true" : "false") + ";"
        "element.dispatchEvent(new Event('change', {bubbles: true}));"
        "return {found: true, checked: !!element.checked};"
        "})()";
    const nlohmann::json result = context.EvaluateJsReturningJson(script);
    if (!result.value("found", false)) {
      return ErrorResponse(ErrorCode::kElementNotFound,
                           "No element matching selector '" + selector + "'");
    }
    return SuccessResponse({{"checked", result.value("checked", checked)}});
  } catch (const std::invalid_argument& exception) {
    return InvalidParams(exception.what());
  }
}

}  // namespace kelpie
