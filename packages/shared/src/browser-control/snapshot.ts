import type { BrowserSnapshot } from "./protocol.js";

/** Fixed page reader. The element handles stay in the adapter, never in model output. */
export function collectBrowserSnapshot(options: { maxElements?: number; maxChars?: number; prefix: string }): {
  snapshot: BrowserSnapshot; targets: Record<string, Element>;
} {
  const maxElements = options.maxElements ?? 200;
  const maxChars = options.maxChars ?? 16_000;
  const elements: { ref: string; role: string; name: string }[] = [];
  const targets: Record<string, Element> = {};
  const lines: string[] = [];
  let truncated = false;
  const clean = (text: string): string => text.replace(/\s+/g, " ").trim().slice(0, 256);
  const content = (node: Node): string => {
    if (node instanceof Element && node.matches("input,textarea,select,script,style,noscript,template,[hidden],[aria-hidden='true']")) return "";
    return node.nodeType === Node.TEXT_NODE ? node.textContent ?? "" : Array.from(node.childNodes).map(content).join(" ");
  };
  const visit = (root: Document | ShadowRoot): void => {
    for (const el of root.querySelectorAll(root instanceof Document ? "body *" : "*")) {
      if (elements.length >= maxElements) { truncated = true; return; }
      const tag = el.tagName.toLowerCase();
      if (["script", "style", "noscript", "template"].includes(tag) || el.closest("[hidden],[aria-hidden='true']")) continue;
      if (el.getClientRects().length === 0) continue;
      const roles: Record<string, string> = { a: "link", button: "button", select: "combobox", textarea: "textbox", h1: "heading", h2: "heading", h3: "heading", nav: "navigation", main: "main", img: "img" };
      const type = el.getAttribute("type") ?? "text";
      const role = el.getAttribute("role") ?? (tag === "input" ? (type === "checkbox" ? "checkbox" : type === "radio" ? "radio" : "textbox") : roles[tag]);
      const labelIds = el.getAttribute("aria-labelledby")?.split(/\s+/) ?? [];
      const labelled = labelIds.map((id) => { const label = root.getElementById(id); return label ? content(label) : ""; }).join(" ").trim();
      const labels = "labels" in el ? Array.from((el as HTMLInputElement).labels ?? []).map(content).join(" ") : "";
      const name = clean(labelled || el.getAttribute("aria-label") || labels || el.getAttribute("alt") || el.getAttribute("placeholder") || content(el));
      if (role || (["p", "li", "td", "th"].includes(tag) && name)) {
        const ref = `${options.prefix}${String(elements.length + 1)}`;
        const line = `[${ref}] ${role ?? tag}${name ? ` ${JSON.stringify(name)}` : ""}`;
        if (lines.join("\n").length + line.length > maxChars) { truncated = true; return; }
        elements.push({ ref, role: role ?? tag, name });
        targets[ref] = el;
        lines.push(line);
      }
      if (el.shadowRoot) visit(el.shadowRoot);
    }
  };
  visit(document);
  const text = `url: ${location.href}\ntitle: ${document.title}\n${lines.join("\n")}`;
  return { targets, snapshot: { url: location.href, title: document.title, elements, text: text.slice(0, maxChars), truncated: truncated || text.length > maxChars } };
}
