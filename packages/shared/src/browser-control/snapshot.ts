import type { BrowserSnapshot } from "./protocol.js";
import { createBoundedDOMReader } from "./dom-reader.js";

/** Fixed value-free reader; serialize through fixedObservationReaderSource to include its primitives. */
export function collectBrowserSnapshot(options: {
  maxElements?: number; maxChars?: number; prefix: string; includeShadow?: boolean; scope?: string; prioritize?: boolean;
}, factory: typeof createBoundedDOMReader = createBoundedDOMReader): { snapshot: BrowserSnapshot; targets: Record<string, Element> } {
  const dom = factory();
  const maxElements = options.maxElements ?? 200, maxChars = options.maxChars ?? 16_000;
  const elements: { ref: string; role: string; name: string }[] = [], targets: Record<string, Element> = {};
  const url = location.href.slice(0, Math.min(4096, Math.floor(maxChars / 2)));
  if (url.length < location.href.length) dom.mark();
  const title = dom.title(Math.min(1024, Math.floor(maxChars / 4)));
  let text = "url: " + url + "\ntitle: " + title;
  const root = dom.scope(options.scope);
  const pool = dom.scan(root instanceof Document ? (root.body as HTMLElement | null) ?? root : root, "*", { includeRoot: !(root instanceof Document), shadow: options.includeShadow !== false, prunePrivate: true });
  const ids = new Map<string, Element>(), labelsFor = new Map<string, Element[]>();
  for (const el of pool.found) {
    const id = dom.attr(el, "id", 1024);
    if (id && !ids.has(id)) ids.set(id, el);
    if (el.tagName.toLowerCase() === "label") {
      const target = dom.attr(el, "for", 1024), labels = labelsFor.get(target) ?? [];
      if (target && labels.length < 8) { labels.push(el); labelsFor.set(target, labels); }
      else if (target) dom.mark();
    }
  }
  const candidates = pool.found, candidateSet = new Set(candidates);
  const priority = (el: Element): number => {
    const tag = el.tagName.toLowerCase(), role = dom.attr(el, "role", 80);
    if (["button", "input", "select", "textarea", "a"].includes(tag) || ["button", "link", "textbox", "combobox", "checkbox", "radio"].includes(role)) return 0;
    if (/^h[1-6]$/.test(tag) || role === "heading") return 1;
    return ["main", "nav"].includes(tag) || ["main", "navigation"].includes(role) ? 2 : 3;
  };
  if (options.prioritize !== false) {
    const priorities = new Map(candidates.map((el) => [el, priority(el)]));
    candidates.sort((a, b) => (priorities.get(a) ?? 3) - (priorities.get(b) ?? 3));
  }
  for (const el of candidates) {
    if (elements.length >= maxElements) { dom.mark(); break; }
    const tag = el.tagName.toLowerCase(), state = dom.state(el);
    if (state.editorAncestor || !dom.visible(el) || ["script", "style", "noscript", "template", "option"].includes(tag)) continue;
    const read = (node: Element): string => dom.text(node, 256).value;
    const labelIds = dom.attr(el, "aria-labelledby", 1024).split(/\s+/).slice(0, 8);
    let labelled = "";
    for (const id of labelIds) {
      const label = ids.get(id);
      if (label?.getRootNode() === el.getRootNode()) labelled += " " + read(label);
      if (labelled.length >= 256) { dom.mark(); break; }
    }
    let associated = "";
    const id = dom.attr(el, "id", 1024);
    if (["input", "textarea", "select"].includes(tag)) {
      const labels = new Set(labelsFor.get(id) ?? []);
      let parent = el.parentElement, depth = 0;
      while (parent && ++depth <= 40) {
        if (parent.tagName.toLowerCase() === "label" && (!options.scope || candidateSet.has(parent))) { labels.add(parent); break; }
        parent = parent.parentElement;
      }
      if (depth > 40) dom.mark();
      for (const label of labels) {
        if (label.getRootNode() !== el.getRootNode()) continue;
        associated += " " + read(label);
        if (associated.length >= 256) { dom.mark(); break; }
      }
    }
    let svgTitle = "";
    if (tag === "svg") {
      let child = el.firstElementChild, checked = 0;
      while (child && ++checked <= 32) {
        if (child.tagName.toLowerCase() === "title") { svgTitle = read(child); break; }
        child = child.nextElementSibling;
      }
      if (checked > 32) dom.mark();
    }
    const roles: Record<string, string> = { button: "button", select: "combobox", textarea: "textbox", nav: "navigation", main: "main", img: "img" };
    const type = dom.attr(el, "type", 32) || "text";
    const inputRole = type === "checkbox" ? "checkbox" : type === "radio" ? "radio" : ["submit", "reset", "button", "image"].includes(type) ? "button" : type === "hidden" ? undefined : "textbox";
    const aria = dom.attr(el, "aria-label", 256);
    const namedSvg = tag === "svg" && [labelled, aria, svgTitle].some((value) => value.trim());
    const role = dom.attr(el, "role", 80) || (tag === "input" ? inputRole : namedSvg ? "img" : tag === "a" && el.hasAttribute("href") ? "link" : /^h[1-6]$/.test(tag) ? "heading" : roles[tag]);
    const name = dom.bounded([labelled, aria, associated, dom.attr(el, "alt", 256), dom.attr(el, "placeholder", 256), svgTitle].find((value) => value.trim()) ?? read(el), 256);
    if (role || (["p", "li", "td", "th"].includes(tag) && name)) {
      const ref = options.prefix + String(elements.length + 1);
      const line = "\n[" + ref + "] " + (role ?? tag) + " " + JSON.stringify(name);
      if (text.length + line.length > maxChars) { dom.mark(); break; }
      text += line; elements.push({ ref, role: role ?? tag, name }); targets[ref] = el;
    }
  }
  return { targets, snapshot: { url, title, elements, text, truncated: dom.truncated } };
}
