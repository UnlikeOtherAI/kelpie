import type { BrowserSnapshot } from "./protocol.js";

/** Fixed, self-contained page reader. It never reads form-control values. */
export function collectBrowserSnapshot(options: {
  maxElements?: number; maxChars?: number; prefix: string; includeShadow?: boolean;
}): { snapshot: BrowserSnapshot; targets: Record<string, Element> } {
  const maxElements = options.maxElements ?? 200;
  const maxChars = options.maxChars ?? 16_000;
  const elements: { ref: string; role: string; name: string }[] = [];
  const targets: Record<string, Element> = {};
  let truncated = false;
  const clean = (text: string, limit = 256): string => {
    const value = text.replace(/\s+/g, " ").trim();
    if (value.length > limit) truncated = true;
    return value.slice(0, limit);
  };
  const url = location.href.slice(0, Math.min(4096, Math.floor(maxChars / 2)));
  const title = clean(document.title, Math.min(1024, Math.floor(maxChars / 4)));
  let text = `url: ${url}\ntitle: ${title}`;
  if (url !== location.href || title !== clean(document.title, document.title.length)) truncated = true;
  let visited = 0;
  const ignored = "input,textarea,select,[contenteditable]:not([contenteditable='false']),script,style,noscript,template,[hidden],[aria-hidden='true']";
  const content = (node: Node, depth = 0): string => {
    if (depth > 40 || (node instanceof Element && (node.matches(ignored) || node.closest("[contenteditable]:not([contenteditable='false'])") || getComputedStyle(node).visibility === "hidden" || getComputedStyle(node).display === "none"))) return "";
    if (node.nodeType === Node.TEXT_NODE) {
      const value = node.textContent ?? "";
      if (value.length > 256) truncated = true;
      return value.slice(0, 256);
    }
    let value = "";
    for (const child of node.childNodes) {
      value += ` ${content(child, depth + 1)}`;
      if (value.length >= 512) { if (child.nextSibling) truncated = true; break; }
    }
    return value;
  };
  const visit = (root: Document | ShadowRoot): void => {
    for (const el of root.querySelectorAll(root instanceof Document ? "body *" : "*")) {
      if (++visited > 5000 || elements.length >= maxElements) { truncated = true; return; }
      const editor = el.closest("[contenteditable]:not([contenteditable='false'])");
      if (editor && editor !== el) continue;
      const tag = el.tagName.toLowerCase();
      const style = getComputedStyle(el);
      if (["script", "style", "noscript", "template", "option"].includes(tag) || el.closest("[hidden],[aria-hidden='true']")) continue;
      if (el.getClientRects().length === 0 || style.visibility === "hidden" || style.visibility === "collapse") continue;
      const roles: Record<string, string> = { button: "button", select: "combobox", textarea: "textbox", nav: "navigation", main: "main", img: "img" };
      const type = el.getAttribute("type") ?? "text";
      const inputRole = type === "checkbox" ? "checkbox" : type === "radio" ? "radio" : ["submit", "reset", "button", "image"].includes(type) ? "button" : type === "hidden" ? undefined : "textbox";
      const labelled = (el.getAttribute("aria-labelledby")?.split(/\s+/) ?? []).map((id) => {
        const label = root.getElementById(id); return label ? content(label) : "";
      }).join(" ").trim();
      const labels = el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement || el instanceof HTMLSelectElement
        ? Array.from(el.labels ?? []).map((label) => content(label)).join(" ") : "";
      const svgTitle = tag === "svg" ? el.querySelector(":scope > title")?.textContent : "";
      const namedSvg = tag === "svg" && [labelled, el.getAttribute("aria-label"), svgTitle].some((value) => value?.trim());
      const role = el.getAttribute("role") ?? (tag === "input" ? inputRole : namedSvg ? "img" : tag === "a" && el.hasAttribute("href") ? "link" : /^h[1-6]$/.test(tag) ? "heading" : roles[tag]);
      const name = clean([labelled, el.getAttribute("aria-label"), labels, el.getAttribute("alt"), el.getAttribute("placeholder"), svgTitle, content(el)].find((value) => value?.trim()) ?? "");
      if (role || (["p", "li", "td", "th"].includes(tag) && name)) {
        const ref = `${options.prefix}${String(elements.length + 1)}`;
        const line = `\n[${ref}] ${role ?? tag} ${JSON.stringify(name)}`;
        if (text.length + line.length > maxChars) { truncated = true; return; }
        text += line;
        elements.push({ ref, role: role ?? tag, name });
        targets[ref] = el;
      }
      if (el.shadowRoot && !editor && options.includeShadow !== false) visit(el.shadowRoot);
    }
  };
  visit(document);
  return { targets, snapshot: { url, title, elements, text, truncated } };
}
