#pragma once

#include <string_view>

namespace kelpie {

inline constexpr std::string_view kVisibleElementsScript = R"JS(
(() => {
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
  return Array.from(document.querySelectorAll("*")).flatMap((element) => {
    const rect = element.getBoundingClientRect();
    if (!rect.width || !rect.height) return [];
    return [{
      tag: element.tagName.toLowerCase(),
      text: (element.innerText || "").trim(),
      selector: selectorFor(element),
      interactable: element.matches("a,button,input,select,textarea,[role=button],[role=link]"),
    }];
  });
})()
)JS";

// Appended inside a page-text snapshot so text and accessible names share the
// same document evaluation. Logos can be readable even when innerText is empty.
inline constexpr std::string_view kPageLabelsScript = R"JS(
const accessibleLabels = root ? Array.from(root.querySelectorAll('img[alt],[aria-label],[aria-labelledby],svg')).flatMap(node => {
  const rect = node.getBoundingClientRect();
  const style = getComputedStyle(node);
  if (!rect.width || !rect.height || style.visibility === 'hidden' || style.display === 'none' || node.closest('[aria-hidden="true"],[hidden]')) return [];
  const references = (node.getAttribute('aria-labelledby') || '').split(/\s+/)
    .map(id => document.getElementById(id)?.textContent || '').join(' ').trim();
  return [node.getAttribute('alt'), node.getAttribute('aria-label'), references,
    node.matches('svg') ? node.querySelector('title')?.textContent : ''].filter(value => value && value.trim()).map(value => value.trim());
}) : [];
)JS";

inline constexpr std::string_view kPageTextScript = R"JS(
(() => {
  const root = document.body;
  const text = root ? root.innerText || "" : "";
  return { text, length: text.length };
})()
)JS";

inline constexpr std::string_view kFormStateScript = R"JS(
(() => {
  const fields = Array.from(document.querySelectorAll("input,textarea,select"))
    .map((element) => ({
      name: element.name || "",
      id: element.id || "",
      type: element.type || element.tagName.toLowerCase(),
      value: element.value,
      checked: !!element.checked,
    }));
  return { fields, count: fields.length };
})()
)JS";

}  // namespace kelpie
