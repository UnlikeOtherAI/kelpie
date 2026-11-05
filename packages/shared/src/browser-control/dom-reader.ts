/** Fixed, bounded DOM primitives. Serialized with each reader, never caller code. */
export function createBoundedDOMReader() {
  let work = 20_000, textBudget = 65_536, styles = 20_000, truncated = false;
  const states = new Map<Element, { visible: boolean; private: boolean; editorAncestor: boolean; unknown: boolean; clip: { left: number; top: number; right: number; bottom: number } }>();
  const mark = (): void => { truncated = true; };
  const attr = (el: Element, name: string, limit = 2048): string => {
    const value = el.getAttribute(name) ?? "";
    if (value.length > limit) mark();
    return value.slice(0, limit);
  };
  const state = (el: Element) => {
    const previous = states.get(el);
    if (previous) return previous;
    let visible = true, privateValue = false, editorAncestor = false, unknown = false, depth = 0;
    const clip = { left: -Infinity, top: -Infinity, right: Infinity, bottom: Infinity };
    for (let node: Element | null = el; node;) {
      if (++depth > 40 || --styles < 0 || --work < 0) { mark(); unknown = true; visible = false; privateValue = true; break; }
      const tag = node.tagName.toLowerCase();
      const editor = node.hasAttribute("contenteditable") && attr(node, "contenteditable", 16) !== "false";
      if (editor && node !== el) editorAncestor = true;
      if (editor || ["input", "textarea", "select", "option", "script", "style", "noscript", "template"].includes(tag)) privateValue = true;
      const style = getComputedStyle(node);
      if (node.hasAttribute("hidden") || attr(node, "aria-hidden", 16) === "true" ||
          style.display === "none" || style.visibility === "hidden" || style.visibility === "collapse" || Number(style.opacity) <= 0) visible = false;
      if (node !== el) {
        const clipX = ["hidden", "clip", "scroll", "auto"].includes(style.overflowX);
        const clipY = ["hidden", "clip", "scroll", "auto"].includes(style.overflowY);
        if (clipX || clipY) {
          const box = node.getBoundingClientRect();
          if (clipX) { clip.left = Math.max(clip.left, box.left); clip.right = Math.min(clip.right, box.right); }
          if (clipY) { clip.top = Math.max(clip.top, box.top); clip.bottom = Math.min(clip.bottom, box.bottom); }
        }
      }
      const parent: Element | null = node.parentElement, boundary: ParentNode | null = node.parentNode;
      node = parent ?? (boundary instanceof ShadowRoot ? boundary.host : null);
    }
    const value = { visible, private: privateValue, editorAncestor, unknown, clip };
    states.set(el, value); return value;
  };
  const visible = (el: Element, viewport = false): boolean => {
    const inspected = state(el);
    if (!inspected.visible) return false;
    const box = el.getBoundingClientRect();
    if (box.width <= 0 || box.height <= 0) return false;
    return !viewport || (Math.max(0, box.left, inspected.clip.left) < Math.min(innerWidth, box.right, inspected.clip.right) &&
      Math.max(0, box.top, inspected.clip.top) < Math.min(innerHeight, box.bottom, inspected.clip.bottom));
  };
  const walk = (root: Node, visit: (node: Node) => "skip" | "stop" | undefined, shadow = false): boolean => {
    const stack: { node: Node; depth: number; sibling: boolean }[] = [{ node: root, depth: 0, sibling: false }];
    let visited = 0, complete = true;
    while (stack.length) {
      if (++visited > 5000 || --work < 0) { mark(); return false; }
      const frame = stack.pop();
      if (!frame) break;
      const { node, depth, sibling } = frame;
      if (sibling && node.nextSibling) stack.push({ node: node.nextSibling, depth, sibling: true });
      const action = visit(node);
      if (action === "stop") { mark(); return false; }
      if (action === "skip") continue;
      const child = node.firstChild;
      const shadowRoot = shadow && node instanceof Element ? node.shadowRoot : null;
      if ((child || shadowRoot) && depth >= 40) { mark(); complete = false; continue; }
      if (shadowRoot) stack.push({ node: shadowRoot, depth: depth + 1, sibling: false });
      if (child) stack.push({ node: child, depth: depth + 1, sibling: true });
    }
    return complete;
  };
  const matches = (el: Element, selector: string, root: Node): boolean => {
    if (selector.includes(String.fromCharCode(92))) throw new Error("UNSUPPORTED_SELECTOR_ESCAPE");
    if (!/:scope/i.test(selector)) return el.matches(selector);
    if ((selector.match(/:scope/gi) ?? []).length > 1) throw new Error("UNSUPPORTED_SCOPE_SELECTOR");
    const anchor = root instanceof Document ? root.documentElement : root;
    if (selector.toLowerCase() === ":scope") return el === anchor;
    const child = /^:scope\s*>\s*([^\s>+~,]+)$/i.exec(selector);
    if (child?.[1]) return el.parentNode === anchor && el.matches(child[1]);
    const descendant = /^:scope\s+([^\s:>+~,]+)$/i.exec(selector);
    if (descendant?.[1]) return el !== anchor && el.matches(descendant[1]);
    throw new Error("UNSUPPORTED_SCOPE_SELECTOR");
  };
  const scan = (root: Node, selector: string, options: { includeRoot?: boolean; limit?: number; readable?: boolean; shadow?: boolean; prunePrivate?: boolean } = {}) => {
    const found: Element[] = [];
    const complete = walk(root, (node) => {
      if (!(node instanceof Element) || (node === root && !options.includeRoot)) return;
      if (options.readable && state(node).private) return "skip";
      if (matches(node, selector, root) && (!options.readable || visible(node))) {
        found.push(node);
        if (found.length >= (options.limit ?? 5000)) return "stop";
      }
      if (options.prunePrivate && (["input", "textarea", "select", "script", "style", "noscript", "template"].includes(node.tagName.toLowerCase()) ||
          (node.hasAttribute("contenteditable") && attr(node, "contenteditable", 16) !== "false"))) return "skip";
    }, options.shadow);
    return { found, complete };
  };
  const scope = (selector?: string): Document | Element => {
    if (!selector) return document;
    const result = scan(document, selector, { limit: 2 });
    const root = result.found[0];
    if (!result.complete || result.found.length !== 1 || !root) throw new Error("OBSERVATION_SCOPE");
    return root;
  };
  const text = (root: Node, limit: number, raw = false, requireComplete = false): { value: string; complete: boolean } => {
    let value = "";
    const complete = walk(root, (node) => {
      if (node instanceof Element && !raw && (state(node).private || !state(node).visible)) return "skip";
      if (!(node instanceof Text)) return;
      const separator = !raw && value && node.length ? " " : "";
      const room = Math.max(0, Math.min(limit - value.length - separator.length, textBudget));
      if (node.length > room && requireComplete) { mark(); return "stop"; }
      const take = Math.min(node.length, Math.max(0, room));
      if (take) value += separator + node.substringData(0, take);
      textBudget -= take;
      if (take < node.length) return "stop";
    });
    return { value: raw ? value : value.replace(/\s+/g, " ").trim(), complete };
  };
  const bounded = (value: string, limit: number): string => {
    if (value.length > limit) mark();
    return value.slice(0, limit).replace(/\s+/g, " ").trim();
  };
  const title = (limit = 1024): string => {
    const found = scan((document.head as HTMLHeadElement | null) ?? document, "title", { includeRoot: true, limit: 2 });
    const first = found.found[0];
    return first ? text(first, limit, true).value.replace(/\s+/g, " ").trim() : "";
  };
  return { attr, state, visible, walk, scan, scope, text, bounded, title, mark, get truncated() { return truncated; } };
}
