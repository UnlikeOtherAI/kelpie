#pragma once

#include <string_view>

namespace kelpie {

inline constexpr std::string_view kVisibleElementsScript = R"JS(
(() => {
  const selectorFor = (element) => {
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
