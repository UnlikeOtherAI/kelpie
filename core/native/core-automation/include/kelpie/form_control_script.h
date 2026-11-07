#pragma once

#include <string>

namespace kelpie {

inline std::string FormControlMutationScript() {
  return R"JS(
function kelpieFormControlPrototype(node) {
  if (window.HTMLInputElement && node instanceof window.HTMLInputElement) return window.HTMLInputElement.prototype;
  if (window.HTMLTextAreaElement && node instanceof window.HTMLTextAreaElement) return window.HTMLTextAreaElement.prototype;
  return null;
}
function kelpieReadFormControlValue(node) {
  if (!node) return '';
  if (typeof node.value === 'string') return node.value;
  if (node.isContentEditable) return node.textContent || '';
  return '';
}
function kelpieWriteFormControlValue(node, value) {
  if (!node) return '';
  var previousValue = kelpieReadFormControlValue(node);
  if (window.HTMLSelectElement && node instanceof window.HTMLSelectElement) {
    node.value = value;
    return previousValue;
  }
  if (node.isContentEditable) {
    node.textContent = value;
    return previousValue;
  }
  var prototype = kelpieFormControlPrototype(node);
  var setter = prototype ? Object.getOwnPropertyDescriptor(prototype, 'value')?.set : null;
  if (setter) setter.call(node, value);
  else if ('value' in node) node.value = value;
  else node.textContent = value;
  var tracker = node._valueTracker;
  if (tracker && typeof tracker.setValue === 'function') {
    tracker.setValue(previousValue);
  }
  return previousValue;
}
function kelpieDispatchFormControlInput(node) {
  node.dispatchEvent(new Event('input', { bubbles: true }));
}
function kelpieDispatchFormControlChange(node) {
  node.dispatchEvent(new Event('change', { bubbles: true }));
}
)JS";
}

}  // namespace kelpie
