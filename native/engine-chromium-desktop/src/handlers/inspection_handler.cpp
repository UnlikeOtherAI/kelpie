#include "inspection_handler.h"

#include <deque>
#include <unordered_map>
#include <unordered_set>

#include "inspection_scripts.h"

namespace kelpie {
namespace {

std::string OptionalString(const nlohmann::json& params, const char* key) {
  const auto it = params.find(key);
  if (it == params.end()) return {};
  return RequireString(params, key);
}

bool OptionalBool(const nlohmann::json& params, const char* key, bool fallback) {
  const auto it = params.find(key);
  if (it == params.end()) return fallback;
  if (!it->is_boolean()) throw std::invalid_argument(std::string(key) + " must be a boolean");
  return it->get<bool>();
}

std::string RoleValue(const nlohmann::json& node) {
  const auto role = node.find("role");
  return role != node.end() && role->is_object() ? role->value("value", std::string()) : std::string();
}

}  // namespace

void InspectionHandler::Register(DesktopRouter& router) const {
  router.Register("find-element", [this](const nlohmann::json& p) { return Find(p, "*", "element"); });
  router.Register("find-button", [this](const nlohmann::json& p) { return Find(p, "button,[role=button]", "button"); });
  router.Register("find-link", [this](const nlohmann::json& p) { return Find(p, "a,[role=link]", "link"); });
  router.Register("find-input", [this](const nlohmann::json& p) { return Find(p, "input,textarea,select,[contenteditable=true]", "input"); });
  router.Register("get-page-text", [this](const nlohmann::json& p) { return PageText(p); });
  router.Register("get-visible-elements", [this](const nlohmann::json& p) { return VisibleElements(p); });
  router.Register("get-form-state", [this](const nlohmann::json& p) { return FormState(p); });
  router.Register("get-accessibility-tree", [this](const nlohmann::json& p) { return AccessibilityTree(p); });
}

nlohmann::json InspectionHandler::Find(const nlohmann::json& params, const char* default_selector,
                                       const char* label) const {
  try {
    std::string text;
    std::string selector = OptionalString(params, "selector");
    std::string role = OptionalString(params, "role");
    if (std::string(label) == "input") {
      const std::string input_label = OptionalString(params, "label");
      const std::string placeholder = OptionalString(params, "placeholder");
      const std::string name = OptionalString(params, "name");
      if (input_label.empty() && placeholder.empty() && name.empty()) {
        return InvalidParams("find-input requires label, placeholder, or name");
      }
      selector = selector.empty() ? std::string(default_selector) : selector;
      const std::string script = R"JS((() => {
        const label = )JS" + JsStringLiteral(input_label) + R"JS(;
        const placeholder = )JS" + JsStringLiteral(placeholder) + R"JS(;
        const name = )JS" + JsStringLiteral(name) + R"JS(;
        const selector = )JS" + JsStringLiteral(selector) + R"JS(;
        const elements = Array.from(document.querySelectorAll(selector));
        const element = elements.find((node) =>
          (!label || (node.labels && Array.from(node.labels).some((item) => (item.innerText || "").includes(label)))) &&
          (!placeholder || node.getAttribute("placeholder") === placeholder) &&
          (!name || node.getAttribute("name") === name));
      const selectorFor = (node) => node.id ? `#${CSS.escape(node.id)}` :
          (() => { const segments=[]; for(let current=node; current && current.nodeType===Node.ELEMENT_NODE && current!==document.body; current=current.parentElement) { const tag=current.tagName.toLowerCase(); const siblings=Array.from(current.parentElement?.children || []).filter((sibling) => sibling.tagName===current.tagName); segments.unshift(siblings.length>1 ? `${tag}:nth-of-type(${siblings.indexOf(current)+1})` : tag); } return segments.length ? `body > ${segments.join(" > ")}` : "body"; })();
        return element ? {found: true, selector: selectorFor(element), tag: element.tagName.toLowerCase(),
          text: element.getAttribute("aria-label") || element.getAttribute("placeholder") || ""} : {found: false};
      })())JS";
      nlohmann::json value;
      const auto result = EvaluateForTab(runtime_, params, script, &value);
      return result.ok ? SuccessResponse({{"kind", label}, {"result", value}}) : ControlError(result);
    }
    text = RequireString(params, "text");
    selector = selector.empty() ? std::string(default_selector) : selector;
    const std::string script = R"JS((() => {
      const text = )JS" + JsStringLiteral(text) + R"JS(;
      const selector = )JS" + JsStringLiteral(selector) + R"JS(;
      const role = )JS" + JsStringLiteral(role) + R"JS(;
      const selectorFor = (element) => {
        if (element === document.documentElement) return "html";
        if (element === document.body) return "body";
        if (element.id) return `#${CSS.escape(element.id)}`;
        const segments = [];
        for (let node = element; node && node.nodeType === Node.ELEMENT_NODE && node !== document.body;
             node = node.parentElement) {
          const tag = node.tagName.toLowerCase();
          const siblings = Array.from(node.parentElement?.children || [])
            .filter((sibling) => sibling.tagName === node.tagName);
          segments.unshift(siblings.length > 1 ? `${tag}:nth-of-type(${siblings.indexOf(node) + 1})` : tag);
        }
        return segments.length ? `body > ${segments.join(" > ")}` : "body";
      };
      const element = Array.from(document.querySelectorAll(selector)).find((node) => {
        const inferredRole = node.getAttribute("role") || ({button:"button", a:"link", input:"textbox", textarea:"textbox", select:"combobox"}[node.tagName.toLowerCase()] || "");
        const ownText = Array.from(node.childNodes).filter((child) => child.nodeType === Node.TEXT_NODE)
          .map((child) => child.textContent || "").join(" ");
        const content = ownText || node.getAttribute("aria-label") || node.value || "";
        return (!role || inferredRole === role) && content.includes(text);
      });
      return element ? {found: true, selector: selectorFor(element), tag: element.tagName.toLowerCase(),
        text: (element.innerText || element.value || "").trim()} : {found: false};
    })())JS";
    nlohmann::json value;
    const auto result = EvaluateForTab(runtime_, params, script, &value);
    return result.ok ? SuccessResponse({{"kind", label}, {"result", value}}) : ControlError(result);
  } catch (const std::invalid_argument& error) {
    return InvalidParams(error.what());
  }
}

nlohmann::json InspectionHandler::Evaluate(const nlohmann::json& params, const std::string& script) const {
  try {
    nlohmann::json value;
    const auto result = EvaluateForTab(runtime_, params, script, &value);
    return result.ok ? SuccessResponse(value) : ControlError(result);
  } catch (const std::invalid_argument& error) {
    return InvalidParams(error.what());
  }
}

nlohmann::json InspectionHandler::VisibleElements(const nlohmann::json& params) const {
  try {
    const bool interactable_only = OptionalBool(params, "interactableOnly", false);
    const bool include_text = OptionalBool(params, "includeText", true);
    std::string script(kVisibleElementsScript);
    script += ".filter((element) => " + std::string(interactable_only ? "element.interactable" : "true") + ")";
    if (!include_text) script += ".map(({text, ...element}) => element)";
    nlohmann::json value;
    const auto result = EvaluateForTab(runtime_, params, script, &value);
    return result.ok ? SuccessResponse({{"elements", value}, {"count", value.is_array() ? value.size() : 0}}) : ControlError(result);
  } catch (const std::invalid_argument& error) { return InvalidParams(error.what()); }
}

nlohmann::json InspectionHandler::PageText(const nlohmann::json& params) const {
  try {
    const std::string selector = OptionalString(params, "selector");
    const std::string mode = OptionalString(params, "mode");
    if (!mode.empty() && mode != "readable" && mode != "full" && mode != "markdown") return InvalidParams("mode is invalid");
    const std::string selected_mode = mode.empty() ? "readable" : mode;
    std::string script = "(() => { const root = " + (selector.empty() ? std::string("document.body") : "document.querySelector(" + JsStringLiteral(selector) + ")") +
        "; if (!root) return {text:'', length:0, mode:" + JsStringLiteral(selected_mode) + "};"
        "const text = " + (selected_mode == "markdown"
          ? "Array.from(root.querySelectorAll('h1,h2,h3,h4,h5,h6,p,li,pre')).map((node) => { const tag=node.tagName.toLowerCase(); const value=(node.innerText || '').trim(); if (!value) return ''; if (tag[0] === 'h') return '#'.repeat(Number(tag[1])) + ' ' + value; if (tag === 'li') return '- ' + value; if (tag === 'pre') return '```\\n' + value + '\\n```'; return value; }).filter(Boolean).join('\\n\\n')"
          : "root.innerText || ''") + "; return {text, length: text.length, mode: " + JsStringLiteral(selected_mode) + "}; })()";
    return Evaluate(params, script);
  } catch (const std::invalid_argument& error) { return InvalidParams(error.what()); }
}

nlohmann::json InspectionHandler::FormState(const nlohmann::json& params) const {
  try {
    const std::string selector = OptionalString(params, "selector");
    std::string script = "(() => { const root = " + (selector.empty() ? std::string("document") : "document.querySelector(" + JsStringLiteral(selector) + ")") +
        "; const fields = root ? Array.from(root.querySelectorAll('input,textarea,select')).map((element) => ({name: element.name || '', id: element.id || '', type: element.type || element.tagName.toLowerCase(), value: element.value, checked: !!element.checked})) : []; return {fields, count: fields.length}; })()";
    return Evaluate(params, script);
  } catch (const std::invalid_argument& error) { return InvalidParams(error.what()); }
}

nlohmann::json InspectionHandler::AccessibilityTree(const nlohmann::json& params) const {
  try {
    TabLease lease;
    auto result = RequireBrowserControl(runtime_).ResolveTab(OptionalTabId(params), OptionalGeneration(params),
                                                             &lease, ControlTimeout(params));
    if (!result.ok) return ControlError(result);
    nlohmann::json ax;
    const std::string root = OptionalString(params, "root");
    if (root.empty()) {
      result = RequireBrowserControl(runtime_).DevTools(lease, "Accessibility.getFullAXTree", {}, &ax,
                                                        ControlTimeout(params));
    } else {
      nlohmann::json document;
      result = RequireBrowserControl(runtime_).DevTools(lease, "DOM.getDocument", {{"depth", 0}}, &document,
                                                        ControlTimeout(params));
      if (!result.ok) return ControlError(result);
      const int node_id = document.value("root", nlohmann::json::object()).value("nodeId", 0);
      nlohmann::json selected;
      result = RequireBrowserControl(runtime_).DevTools(lease, "DOM.querySelector",
          {{"nodeId", node_id}, {"selector", root}}, &selected, ControlTimeout(params));
      if (!result.ok) return ControlError(result);
      result = RequireBrowserControl(runtime_).DevTools(lease, "Accessibility.getPartialAXTree",
          {{"nodeId", selected.value("nodeId", 0)}, {"fetchRelatives", true}}, &ax, ControlTimeout(params));
    }
    if (!result.ok) return ControlError(result);
    nlohmann::json nodes = ax.value("nodes", nlohmann::json::array());
    if (params.contains("maxDepth")) {
      const int max_depth = RequireBoundedInteger(params, "maxDepth", 0, 100);
      std::unordered_set<std::string> child_ids;
      for (const auto& node : nodes) {
        for (const auto& child : node.value("childIds", nlohmann::json::array())) {
          if (child.is_string()) child_ids.insert(child.get<std::string>());
        }
      }
      std::deque<std::pair<std::string, int>> pending;
      for (const auto& node : nodes) {
        const std::string id = node.value("nodeId", std::string());
        if (!id.empty() && child_ids.find(id) == child_ids.end()) pending.emplace_back(id, 0);
      }
      std::unordered_map<std::string, int> depths;
      while (!pending.empty()) {
        const auto [id, depth] = pending.front();
        pending.pop_front();
        if (depths.emplace(id, depth).second == false || depth >= max_depth) continue;
        const auto node = std::find_if(nodes.begin(), nodes.end(), [&](const nlohmann::json& item) {
          return item.value("nodeId", std::string()) == id;
        });
        if (node == nodes.end()) continue;
        for (const auto& child : node->value("childIds", nlohmann::json::array())) {
          if (child.is_string()) pending.emplace_back(child.get<std::string>(), depth + 1);
        }
      }
      nodes.erase(std::remove_if(nodes.begin(), nodes.end(), [&](const nlohmann::json& node) {
        const auto depth = depths.find(node.value("nodeId", std::string()));
        return depth == depths.end() || depth->second > max_depth;
      }), nodes.end());
    }
    if (OptionalBool(params, "interactableOnly", false)) {
      const std::unordered_set<std::string> interactable = {"button", "checkbox", "combobox", "link", "textbox"};
      nodes.erase(std::remove_if(nodes.begin(), nodes.end(), [&](const nlohmann::json& node) {
        return interactable.find(RoleValue(node)) == interactable.end();
      }), nodes.end());
    }
    return SuccessResponse({{"nodes", nodes}, {"count", nodes.size()},
                            {"tab", result.tab ? TabJson(*result.tab) : nlohmann::json::object()}});
  } catch (const std::invalid_argument& error) {
    return InvalidParams(error.what());
  }
}

}  // namespace kelpie
