#include "kelpie/native_extension_schema.h"
#include "kelpie/native_inference_schema.h"
#include <set>
namespace kelpie {
nlohmann::json NativeExtensionInputSchema(std::string_view endpoint) {
  if (endpoint.substr(0, 3) == "ai-") return InferenceNativeExtensionInputSchema(endpoint);
  nlohmann::json properties = nlohmann::json::object();
  nlohmann::json required = nlohmann::json::array();
  const auto string = [&properties](const char* name, bool required_field = false) {
    properties[name] = {{"type", "string"}, {"minLength", required_field ? 1 : 0}};
  };
  const auto integer = [&properties](const char* name, int minimum = 0) {
    properties[name] = {{"type", "integer"}, {"minimum", minimum}};
  };
  const auto number = [&properties](const char* name) {
    properties[name] = {{"type", "number"}};
  };
  const auto tab_scoped = [&properties] {
    properties["tabId"] = {{"type", "string"}, {"minLength", 1}};
    properties["generation"] = {{"type", "integer"}, {"minimum", 0}};
    properties["timeout"] = {{"type", "integer"}, {"minimum", 1}, {"maximum", 30000}};
  };
  const auto require = [&required](const char* name) { required.push_back(name); };
  const bool scoped = endpoint == "navigate" || endpoint == "back" || endpoint == "forward" ||
      endpoint == "reload" || endpoint == "get-current-url" ||
      endpoint == "switch-tab" || endpoint == "close-tab" || endpoint == "get-dom" ||
      endpoint == "query-selector" || endpoint == "query-selector-all" ||
      endpoint == "get-element-text" || endpoint == "get-attributes" || endpoint == "evaluate" ||
      endpoint == "wait-for-element" || endpoint == "wait-for-navigation" || endpoint == "click" ||
      endpoint == "fill" || endpoint == "type" || endpoint == "select-option" || endpoint == "check" ||
      endpoint == "uncheck" || endpoint == "press-key" || endpoint == "scroll" ||
      endpoint == "scroll-to-top" || endpoint == "scroll-to-bottom" || endpoint == "screenshot" ||
      endpoint == "screenshot-annotated" || endpoint == "get-cookies" || endpoint == "set-cookie" ||
      endpoint == "delete-cookies" || endpoint == "clear-cookies" || endpoint == "get-storage" ||
      endpoint == "set-storage" || endpoint == "clear-storage" || endpoint == "get-dialog" ||
      endpoint == "handle-dialog" || endpoint == "find-element" || endpoint == "find-button" ||
      endpoint == "find-link" || endpoint == "find-input" || endpoint == "get-page-text" ||
      endpoint == "get-visible-elements" || endpoint == "get-form-state" || endpoint == "get-accessibility-tree";
  if (scoped) tab_scoped();

  if (endpoint == "navigate" || endpoint == "set-home") { string("url", true); require("url"); }
  else if (endpoint == "new-tab") { string("url", true); properties["timeout"] = {{"type", "integer"}, {"minimum", 1}, {"maximum", 30000}}; }
  else if (endpoint == "evaluate") { string("expression", true); require("expression"); }
  else if (endpoint == "query-selector" || endpoint == "query-selector-all" || endpoint == "get-element-text" || endpoint == "get-attributes") { string("selector", true); require("selector"); }
  else if (endpoint == "get-dom") string("selector");
  else if (endpoint == "wait-for-element") {
    string("selector", true);
    properties["state"] = {{"enum", {"attached", "visible", "hidden"}}};
    require("selector");
  }
  else if (endpoint == "click" || endpoint == "check" || endpoint == "uncheck") { string("selector", true); require("selector"); }
  else if (endpoint == "fill" || endpoint == "select-option") { string("selector", true); string("value"); require("selector"); require("value"); }
  else if (endpoint == "type") { string("text", true); string("selector"); require("text"); }
  else if (endpoint == "press-key") {
    string("key", true); string("code");
    properties["modifiers"] = {{"type", "array"}, {"items", {{"type", "string"},
        {"enum", {"Alt", "Control", "Meta", "Shift"}}}}};
    require("key");
  }
  else if (endpoint == "scroll") {
    number("deltaX");
    number("deltaY");
    require("deltaX"); require("deltaY");
  }
  else if (endpoint == "screenshot" || endpoint == "screenshot-annotated") { properties["format"]={{"const","png"}}; }
  else if (endpoint == "get-cookies") { string("url"); string("name"); }
  else if (endpoint == "set-cookie") {
    string("name", true); string("value"); string("url"); string("domain"); string("path");
    string("expires"); properties["httpOnly"] = {{"type", "boolean"}};
    properties["secure"] = {{"type", "boolean"}};
    properties["sameSite"] = {{"enum", {"Strict", "Lax", "None", "strict", "lax", "none"}}};
    require("name"); require("value");
  } else if (endpoint == "delete-cookies") {
    string("name"); string("domain"); properties["deleteAll"]={{"type","boolean"}};
  }
  else if (endpoint == "get-storage") { properties["type"]={{"enum",{"local","session"}}}; string("key"); }
  else if (endpoint == "set-storage") { properties["type"]={{"enum",{"local","session"}}}; string("key",true); string("value"); require("key"); require("value"); }
  else if (endpoint == "clear-storage") properties["type"]={{"enum",{"local","session","both"}}};
  else if (endpoint == "handle-dialog") { properties["action"]={{"enum",{"accept","dismiss"}}}; string("promptText"); require("action"); }
  else if (endpoint == "find-element") {
    string("text", true); string("role"); string("selector"); require("text");
  } else if (endpoint == "find-button" || endpoint == "find-link") {
    string("text", true); require("text");
  } else if (endpoint == "find-input") {
    string("label"); string("placeholder"); string("name");
  } else if (endpoint == "get-page-text") {
    properties["mode"] = {{"enum", {"readable", "full", "markdown"}}}; string("selector");
  } else if (endpoint == "get-visible-elements") {
    properties["interactableOnly"] = {{"type", "boolean"}};
    properties["includeText"] = {{"type", "boolean"}};
  } else if (endpoint == "get-form-state") {
    string("selector");
  } else if (endpoint == "get-accessibility-tree") {
    string("root"); properties["interactableOnly"] = {{"type", "boolean"}};
    integer("maxDepth", 0);
    properties["maxDepth"]["maximum"] = 100;
  }
  else if (endpoint == "toast") { string("message", true); require("message"); }
  else if (endpoint == "set-fullscreen") { properties["enabled"]={{"type","boolean"}}; require("enabled"); }
  else if (endpoint == "resize-viewport") {
    integer("width", 1); integer("height", 1);
    properties["width"]["maximum"] = 16384; properties["height"]["maximum"] = 16384;
    require("width"); require("height");
  }
  else if (endpoint == "bookmarks-add") { string("url",true); string("title"); require("url"); }
  else if (endpoint == "bookmarks-remove") { string("id",true); require("id"); }
  else if (endpoint == "history-list" || endpoint == "get-history") integer("limit",1);
  else if (endpoint == "get-tabs") {
    properties["timeout"] = {{"type", "integer"}, {"minimum", 1}, {"maximum", 30000}};
  } else if (endpoint == "get-console-messages") {
    properties["level"] = {{"enum", {"log", "warn", "error", "info", "debug"}}};
    string("since"); integer("limit", 1);
  } else if (endpoint == "get-network-log") {
    string("type"); string("since");
    properties["status"] = {{"enum", {"success", "error", "pending"}}};
    integer("limit", 1);
  }
  return {{"type", "object"}, {"properties", std::move(properties)}, {"required", std::move(required)}, {"additionalProperties", false}};
}

bool NativeExtensionMutates(std::string_view endpoint) {
  static const std::set<std::string> reads = {
    "get-current-url", "get-home", "bookmarks-list", "history-list", "screenshot", "screenshot-annotated",
    "get-dom", "query-selector", "query-selector-all", "get-element-text", "get-attributes",
    "get-device-info", "get-capabilities", "get-tabs", "get-network-log", "get-console-messages", "get-js-errors",
    "get-dialog", "get-storage", "get-cookies", "get-fullscreen", "get-renderer", "get-viewport-preset", "get-viewport",
    "get-debug-overlay", "get-tap-calibration", "get-ai-status", "ai-status", "ai-models", "ai-endpoints", "ai-endpoint-health",
    "get-partitions", "find-element", "find-button", "find-link", "find-input", "get-page-text", "get-visible-elements",
    "get-form-state", "get-accessibility-tree", "get-input-state", "get-clipboard", "wait-for-element", "wait-for-navigation"
  };
  return reads.count(std::string(endpoint)) == 0;
}

}
