#pragma once

#include <string>

namespace kelpie {

inline std::string ElementSelectorBuilderScript() {
  return R"JS(
function kelpieEscapeIdentifier(value) {
  if (window.CSS && typeof window.CSS.escape === 'function') {
    return window.CSS.escape(String(value));
  }
  return String(value).replace(/([ !"#$%&'()*+,./:;<=>?@[\\\]^`{|}~])/g, '\\$1');
}
function kelpieEscapeAttribute(value) {
  return String(value).replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}
function kelpieBuildSelector(node) {
  if (!node || node.nodeType !== 1) return null;
  function identifiesNode(candidate) {
    if (candidate.length > 2000) return false;
    try {
      var matches = document.querySelectorAll(candidate);
      return matches.length === 1 && matches[0] === node;
    } catch (error) { return false; }
  }
  if (node.id) {
    var id = '#' + kelpieEscapeIdentifier(node.id);
    if (identifiesNode(id)) return id;
  }
  var segments = [];
  var current = node;
  while (current && current.nodeType === 1) {
    var tag = current.tagName.toLowerCase();
    var segment = tag;
    if (current.id) {
      var identified = [tag + '#' + kelpieEscapeIdentifier(current.id)].concat(segments).join(' > ');
      if (identifiesNode(identified)) return identified;
    }
    var name = current.getAttribute && current.getAttribute('name');
    if (name) {
      var named = tag + '[name="' + kelpieEscapeAttribute(name) + '"]';
      var namedPath = [named].concat(segments).join(' > ');
      if (identifiesNode(namedPath)) return namedPath;
    }
    var parent = current.parentElement;
    if (parent) {
      var index = 1;
      var sibling = current;
      while ((sibling = sibling.previousElementSibling)) {
        if (sibling.tagName === current.tagName) index += 1;
      }
      segment += ':nth-of-type(' + index + ')';
    }
    segments.unshift(segment);
    var candidate = segments.join(' > ');
    if (identifiesNode(candidate)) return candidate;
    current = parent;
  }
  return null;
}
)JS";
}

}  // namespace kelpie
