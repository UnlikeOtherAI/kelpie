#include "desktop_input_planner.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <optional>
#include <sstream>

namespace kelpie::desktop_input {
namespace {

Plan Failure(std::string code, std::string message) { return {false, std::move(code), std::move(message)}; }

bool IsTextKind(const std::string& kind) {
  return kind == "text" || kind == "search" || kind == "email" || kind == "url" || kind == "tel" ||
         kind == "password" || kind == "textarea" || kind == "contenteditable";
}

Json KeyEvent(const char* type, const char* key, const char* code, int virtual_key, int modifiers = 0) {
  return {{"method", "Input.dispatchKeyEvent"}, {"params", {{"type", type}, {"key", key}, {"code", code},
      {"windowsVirtualKeyCode", virtual_key}, {"nativeVirtualKeyCode", virtual_key}, {"modifiers", modifiers}}}};
}

void AddKeyPair(std::vector<Json>* commands, const char* key, const char* code, int virtual_key, int modifiers = 0) {
  commands->push_back(KeyEvent("keyDown", key, code, virtual_key, modifiers));
  commands->push_back(KeyEvent("keyUp", key, code, virtual_key, modifiers));
}

void AddMouseClick(std::vector<Json>* commands, const Target& target) {
  Json pressed = {{"type", "mousePressed"}, {"x", target.x}, {"y", target.y},
                  {"button", "left"}, {"clickCount", 1}};
  Json released = pressed;
  released["type"] = "mouseReleased";
  commands->push_back({{"method", "Input.dispatchMouseEvent"}, {"params", std::move(pressed)}});
  commands->push_back({{"method", "Input.dispatchMouseEvent"}, {"params", std::move(released)}});
}

void AddControlA(std::vector<Json>* commands) {
  commands->push_back(KeyEvent("keyDown", "Control", "ControlLeft", 17, 2));
  commands->push_back(KeyEvent("keyDown", "a", "KeyA", 65, 2));
  commands->push_back(KeyEvent("keyUp", "a", "KeyA", 65, 2));
  commands->push_back(KeyEvent("keyUp", "Control", "ControlLeft", 17));
}

bool IsValidModifier(const std::string& modifier) {
  return modifier == "Alt" || modifier == "Control" || modifier == "Meta" || modifier == "Shift";
}

std::optional<int> VirtualKey(const std::string& key, const std::string& code) {
  if (code.size() == 4 && code.rfind("Key", 0) == 0 && code[3] >= 'A' && code[3] <= 'Z') return code[3];
  if (code.size() == 6 && code.rfind("Digit", 0) == 0 && code[5] >= '0' && code[5] <= '9') return code[5];
  if (key.size() == 1 && static_cast<unsigned char>(key[0]) < 128) return std::toupper(static_cast<unsigned char>(key[0]));
  if (key == "Enter") return 13;
  if (key == "Backspace") return 8;
  if (key == "Tab") return 9;
  if (key == "Escape") return 27;
  if (key == " ") return 32;
  if (key == "Home") return 36;
  if (key == "End") return 35;
  if (key == "ArrowLeft") return 37;
  if (key == "ArrowUp") return 38;
  if (key == "ArrowDown") return 40;
  if (key == "ArrowRight") return 39;
  if (key == "Delete") return 46;
  if (key == "PageUp") return 33;
  if (key == "PageDown") return 34;
  if (key == "Control") return 17;
  if (key == "Shift") return 16;
  if (key == "Alt") return 18;
  return std::nullopt;
}

int Modifiers(const Json& request, std::string* error) {
  const auto modifiers = request.find("modifiers");
  if (modifiers == request.end()) return 0;
  if (!modifiers->is_array()) { *error = "modifiers must be an array"; return -1; }
  int mask = 0;
  for (const auto& value : *modifiers) {
    if (!value.is_string() || !IsValidModifier(value.get<std::string>())) {
      *error = "modifiers must contain Alt, Control, Meta, or Shift"; return -1;
    }
    const std::string modifier = value.get<std::string>();
    if (modifier == "Alt") mask |= 1;
    else if (modifier == "Control") mask |= 2;
    else if (modifier == "Meta") mask |= 4;
    else if (modifier == "Shift") mask |= 8;
  }
  return mask;
}

bool Interactable(const Target& target) { return target.found && target.visible && target.enabled && !target.occluded; }

}  // namespace

std::string TargetInspectionScript(const std::optional<std::string>& selector, bool scroll_into_view) {
  const std::string find = selector ? "document.querySelector(" + Json(*selector).dump() + ")" : "document.activeElement";
  const std::string scroll = scroll_into_view ? "e.scrollIntoView({block:'center',inline:'center'});" : "";
  return "(()=>{const e=" + find + ";if(!e)return {found:false};" + scroll +
      "const r=e.getBoundingClientRect(),s=getComputedStyle(e),hit=document.elementFromPoint(r.left+r.width/2,r.top+r.height/2),"
      "kind=e.isContentEditable?'contenteditable':(e.tagName==='TEXTAREA'?'textarea':(e.tagName==='SELECT'?(e.multiple?'select-multiple':'select-one'):(e.type||e.tagName).toLowerCase()));"
      "return {found:true,x:r.left+r.width/2,y:r.top+r.height/2,visible:r.width>0&&r.height>0&&s.visibility!=='hidden'&&s.display!=='none',"
      "enabled:!e.matches(':disabled'),occluded:!hit||(hit!==e&&!e.contains(hit)),editable:!!(e.isContentEditable||(e.tagName==='TEXTAREA'&&!e.readOnly)||(e.tagName==='INPUT'&&"
      "['text','search','email','url','tel','password'].includes((e.type||'text').toLowerCase())&&!e.readOnly)),kind,value:e.isContentEditable?(e.textContent||''):(e.value||''),checked:!!e.checked,"
      "selectionStart:('selectionStart'in e&&typeof e.selectionStart==='number')?e.selectionStart:null,selectionEnd:('selectionEnd'in e&&typeof e.selectionEnd==='number')?e.selectionEnd:null,"
      "options:e.tagName==='SELECT'?Array.from(e.options).map(o=>({value:o.value,disabled:o.matches(':disabled'),selected:o.selected})):[]};})()";
}

std::optional<Target> ParseTarget(const Json& value, std::string* error) {
  if (!value.is_object()) { if (error) *error = "Target inspection did not return an object"; return std::nullopt; }
  Target target;
  const auto found = value.find("found");
  if (found == value.end() || !found->is_boolean()) { if (error) *error = "Target inspection is malformed"; return std::nullopt; }
  target.found = found->get<bool>();
  if (!target.found) return target;
  for (const char* key : {"visible", "enabled", "occluded", "editable", "checked"}) {
    const auto field = value.find(key);
    if (field == value.end() || !field->is_boolean()) { if (error) *error = std::string("Target ") + key + " is malformed"; return std::nullopt; }
  }
  for (const char* key : {"kind", "value"}) {
    const auto field = value.find(key);
    if (field == value.end() || !field->is_string()) { if (error) *error = std::string("Target ") + key + " is malformed"; return std::nullopt; }
  }
  for (const char* key : {"x", "y"}) {
    const auto field = value.find(key);
    if (field == value.end() || !field->is_number() || !std::isfinite(field->get<double>())) {
      if (error) *error = std::string("Target ") + key + " is malformed"; return std::nullopt;
    }
  }
  target.visible = value["visible"].get<bool>(); target.enabled = value["enabled"].get<bool>();
  target.occluded = value["occluded"].get<bool>(); target.editable = value["editable"].get<bool>();
  target.checked = value["checked"].get<bool>(); target.kind = value["kind"].get<std::string>();
  target.value = value["value"].get<std::string>(); target.x = value["x"].get<double>(); target.y = value["y"].get<double>();
  for (const auto [key, destination] : {std::pair{"selectionStart", &target.selection_start}, std::pair{"selectionEnd", &target.selection_end}}) {
    const auto field = value.find(key);
    if (field == value.end() || field->is_null()) continue;
    std::optional<std::size_t> position;
    if (field->is_number_unsigned()) position = field->get<std::size_t>();
    if (field->is_number_integer() && field->get<std::int64_t>() >= 0) position = static_cast<std::size_t>(field->get<std::int64_t>());
    if (!position || *position > target.value.size()) {
      if (error) *error = std::string("Target ") + key + " is malformed"; return std::nullopt;
    }
    *destination = *position;
  }
  const auto options = value.find("options");
  if (options == value.end() || !options->is_array()) { if (error) *error = "Target options are malformed"; return std::nullopt; }
  for (const auto& option : *options) {
    if (!option.is_object() || !option.contains("value") || !option["value"].is_string() || !option.contains("disabled") ||
        !option["disabled"].is_boolean() || !option.contains("selected") || !option["selected"].is_boolean()) {
      if (error) *error = "Target option is malformed"; return std::nullopt;
    }
    target.options.push_back({option["value"].get<std::string>(), option["disabled"].get<bool>(), option["selected"].get<bool>()});
  }
  return target;
}

Plan PlanTrustedInput(const Json& request, const std::optional<Target>& target) {
  if (!request.is_object() || !request.contains("type") || !request["type"].is_string()) return Failure("INVALID_PARAMS", "Input type is required");
  const std::string type = request["type"].get<std::string>();
  if (type == "key") {
    const auto key = request.find("key");
    if (key == request.end() || !key->is_string() || key->get<std::string>().empty()) return Failure("INVALID_PARAMS", "key is required");
    std::string code;
    if (const auto code_value = request.find("code"); code_value != request.end()) {
      if (!code_value->is_string()) return Failure("INVALID_PARAMS", "code must be a string");
      code = code_value->get<std::string>();
    }
    std::string modifier_error; const int modifiers = Modifiers(request, &modifier_error);
    if (modifiers < 0) return Failure("INVALID_PARAMS", modifier_error);
    const auto virtual_key = VirtualKey(key->get<std::string>(), code);
    if (!virtual_key) return Failure("UNSUPPORTED", "key does not have a supported native virtual key code");
    Plan plan; plan.ok = true; AddKeyPair(&plan.commands, key->get<std::string>().c_str(), code.c_str(), *virtual_key, modifiers); return plan;
  }
  if (type != "click" && type != "fill" && type != "type" && type != "selectOption" && type != "setChecked") return Failure("UNSUPPORTED", "Unsupported native input type");
  if (!target || !target->found) return Failure("ELEMENT_NOT_FOUND", "No matching element exists");
  if (!Interactable(*target)) return Failure("ELEMENT_NOT_INTERACTABLE", "Element is hidden, disabled, or covered");
  Plan plan; plan.ok = true;
  if (type == "click") { AddMouseClick(&plan.commands, *target); return plan; }
  if (type == "setChecked") {
    const auto checked = request.find("checked");
    if (checked == request.end() || !checked->is_boolean()) return Failure("INVALID_PARAMS", "checked must be a boolean");
    if (target->kind != "checkbox") return Failure("UNSUPPORTED", "setChecked requires a checkbox");
    if (target->checked != checked->get<bool>()) AddMouseClick(&plan.commands, *target);
    plan.expected = {{"kind", "checked"}, {"value", checked->get<bool>()}}; return plan;
  }
  if (type == "selectOption") {
    const auto wanted = request.find("value");
    if (wanted == request.end() || !wanted->is_string()) return Failure("INVALID_PARAMS", "value is required");
    if (target->kind != "select-one") return Failure("UNSUPPORTED", "selectOption requires a single-select element");
    const auto option = std::find_if(target->options.begin(), target->options.end(), [&](const Target::Option& item) { return item.value == wanted->get<std::string>(); });
    if (option == target->options.end()) return Failure("ELEMENT_NOT_FOUND", "The requested option does not exist");
    if (option->disabled) return Failure("ELEMENT_NOT_INTERACTABLE", "The requested option is disabled");
    if (target->value != option->value) {
      AddMouseClick(&plan.commands, *target); AddKeyPair(&plan.commands, "Home", "Home", 36);
      for (auto current = target->options.begin(); current != option; ++current) if (!current->disabled) AddKeyPair(&plan.commands, "ArrowDown", "ArrowDown", 40);
      AddKeyPair(&plan.commands, "Enter", "Enter", 13);
    }
    plan.expected = {{"kind", "value"}, {"value", option->value}}; return plan;
  }
  const char* text_key = type == "fill" ? "value" : "text";
  const auto text = request.find(text_key);
  if (text == request.end() || !text->is_string()) return Failure("INVALID_PARAMS", std::string(text_key) + " must be a string");
  if (!target->editable || !IsTextKind(target->kind)) return Failure("UNSUPPORTED", "Text input requires a text-capable editable element");
  const bool has_selector = request.contains("selector");
  if (has_selector && (!request["selector"].is_string() || request["selector"].get<std::string>().empty())) {
    return Failure("INVALID_PARAMS", "selector must be a non-empty string");
  }
  if (has_selector) AddMouseClick(&plan.commands, *target);
  if (type == "fill") {
    AddControlA(&plan.commands);
    AddKeyPair(&plan.commands, "Backspace", "Backspace", 8);
    plan.commands.push_back({{"method", "Input.insertText"}, {"params", {{"text", text->get<std::string>()}}}});
    plan.expected = {{"kind", "value"}, {"value", text->get<std::string>()}};
  } else if (has_selector) {
    AddKeyPair(&plan.commands, "End", "End", 35);
    plan.commands.push_back({{"method", "Input.insertText"}, {"params", {{"text", text->get<std::string>()}}}});
    plan.expected = {{"kind", "value"}, {"value", target->value + text->get<std::string>()}};
  } else {
    if (!target->selection_start || !target->selection_end || *target->selection_start > *target->selection_end) {
      return Failure("UNSUPPORTED", "Typing without a selector requires a focused text control with a selection");
    }
    const std::string expected = target->value.substr(0, *target->selection_start) + text->get<std::string>() +
                                 target->value.substr(*target->selection_end);
    plan.commands.push_back({{"method", "Input.insertText"}, {"params", {{"text", text->get<std::string>()}}}});
    plan.expected = {{"kind", "value"}, {"value", expected}};
  }
  return plan;
}

bool MatchesExpectedState(const Target& target, const Json& expected) {
  if (!expected.is_object() || !expected.contains("kind") || !expected["kind"].is_string() || !expected.contains("value")) return false;
  const std::string kind = expected["kind"].get<std::string>();
  if (kind == "checked") return expected["value"].is_boolean() && target.checked == expected["value"].get<bool>();
  if (!expected["value"].is_string()) return false;
  const std::string value = expected["value"].get<std::string>();
  return kind == "value" && target.value == value;
}

}  // namespace kelpie::desktop_input
