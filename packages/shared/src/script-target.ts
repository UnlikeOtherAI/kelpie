import type { ScriptTarget } from "./script-workflow.js";

export interface ScriptTargetResult {
  ok: boolean;
  error?: string;
  token?: string;
  documentId?: string;
  x?: number;
  y?: number;
  width?: number;
  viewportWidth?: number;
  viewportHeight?: number;
  height?: number;
  inputGuarantee?: "synthetic-coordinate";
  mayHaveCompleted?: boolean;
  visible?: boolean;
  enabled?: boolean;
  sensitive?: boolean;
  editable?: boolean;
  focused?: boolean;
}

/**
 * Fixed ephemeral reader for a private renderer world. Self-contained for native generation.
 * Resolution stores object identity; preflight never silently retargets after animation.
 * Optional dispatch is atomic synthetic coordinate input, never advertised as trusted input.
 */
export function resolveScriptTarget(target: ScriptTarget, key: string, token?: string, dispatch = false, edit?: { action: "fill" | "type"; text: string }, observe = false): ScriptTargetResult {
  interface Entry { element: Element; document: Document; inputType?: string; readOnly?: boolean; rectX: number; rectY: number; rectWidth: number; rectHeight: number; x: number; y: number; width: number; height: number; coordinate: boolean; url: string; viewportWidth: number; viewportHeight: number };
  interface State { document: Document; documentId: string; next: number; entries: Record<string, Entry> };
  const registry = window as unknown as Record<string, State | undefined>;
  let state = registry[key];
  if (state?.document !== document) {
    state = { document, documentId: String(Date.now()) + "-" + Math.random().toString(36).slice(2), next: 0, entries: Object.create(null) as Record<string, Entry> };
    Object.defineProperty(window, key, { configurable: true, value: state });
  }
  const fail = (error: string): ScriptTargetResult => ({ ok: false, error, mayHaveCompleted: false });
  if ((dispatch && edit) || (observe && (dispatch || edit))) return fail("INVALID_TARGET_OPERATION");
  const budget = { limited: false };
  const isLimited = (): boolean => budget.limited;
  const normalized = (s: string): string => {
    if (s.length > 2048) { budget.limited = true; return ""; }
    return s.replace(/\s+/g, " ").trim();
  };
  let styleVisits = 0;
  const visibleBox = (el: Element): { x: number; y: number; width: number; height: number } | null => {
    if (!el.isConnected) return null;
    const r = el.getBoundingClientRect();
    let left = Math.max(0, r.x), top = Math.max(0, r.y);
    let right = Math.min(innerWidth, r.x + r.width), bottom = Math.min(innerHeight, r.y + r.height);
    let depth = 0;
    for (let parent: Element | null = el; parent; parent = parent.parentElement) {
      if (++depth > 64 || ++styleVisits > 20000) { budget.limited = true; return null; }
      const style = getComputedStyle(parent);
      if (style.visibility !== "visible" || style.display === "none" || Number(style.opacity) === 0) return null;
      if (parent !== el) {
        const clip = parent.getBoundingClientRect();
        if (["hidden", "clip", "auto", "scroll"].includes(style.overflowX)) {
          left = Math.max(left, clip.x); right = Math.min(right, clip.x + clip.width);
        }
        if (["hidden", "clip", "auto", "scroll"].includes(style.overflowY)) {
          top = Math.max(top, clip.y); bottom = Math.min(bottom, clip.y + clip.height);
        }
      }
    }
    return right > left && bottom > top ? { x: left, y: top, width: right - left, height: bottom - top } : null;
  };
  const visible = (el: Element): boolean => visibleBox(el) !== null;
  const boundedText = (el: Element): string => {
    const reader = document.createTreeWalker(el, 0xFFFFFFFF);
    let text = "", count = 0;
    for (let node = reader.nextNode(); node; node = reader.nextNode()) {
      if (++count > 256) { budget.limited = true; return ""; }
      if (node.nodeType !== 3) continue;
      if (text.length + (node.textContent?.length ?? 0) > 2048) { budget.limited = true; return ""; }
      text += node.textContent ?? "";
    }
    return text;
  };
  const enabled = (el: Element): boolean => !el.matches(":disabled") && !el.closest('[inert],[aria-disabled="true"]') && !(el instanceof HTMLButtonElement && el.disabled) && !(el instanceof HTMLInputElement && el.disabled) && !(el instanceof HTMLTextAreaElement && el.disabled) && !(el instanceof HTMLSelectElement && el.disabled);
  const editable = (el: Element): boolean => (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) && !el.readOnly && !el.disabled && (el instanceof HTMLTextAreaElement || ["text", "search", "tel", "url", "email", "password"].includes(el.type));
  const eligible = (el: Element): boolean => visible(el) && (observe || enabled(el));
  const accessibleName = (el: Element): string => {
    const labelledBy = el.getAttribute("aria-labelledby");
    if (labelledBy && labelledBy.length > 2048) { budget.limited = true; return ""; }
    if (labelledBy) {
      const references = labelledBy.split(/\s+/);
      if (references.length > 32) { budget.limited = true; return ""; }
      return normalized(references.map(id => { const label = document.getElementById(id); return label ? boundedText(label) : ""; }).join(" "));
    }
    const aria = el.getAttribute("aria-label");
    if (aria !== null) { if (aria.length > 2048) { budget.limited = true; return ""; } return normalized(aria); }
    if (el instanceof HTMLInputElement && ["button", "submit", "reset"].includes(el.type)) return normalized(el.value.length ? el.value : (el.type === "submit" ? "Submit" : el.type === "reset" ? "Reset" : ""));
    if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement || el instanceof HTMLSelectElement) {
      // Inputs such as image buttons may have no label collection.
      if ((el.labels?.length ?? 0) > 32) { budget.limited = true; return ""; }
      const labels = Array.from(el.labels ?? []).map(boundedText).join(" ");
      return normalized(labels.length ? labels : (el.getAttribute("alt") ?? el.getAttribute("title") ?? ""));
    }
    return normalized(boundedText(el));
  };
  const role = (el: Element): string => {
    const explicit = el.getAttribute("role");
    if (explicit) { if (explicit.length > 64) { budget.limited = true; return ""; } return explicit.split(/\s+/)[0] ?? ""; }
    const tag = el.tagName.toLowerCase();
    if (tag === "button") return "button";
    if (tag === "a" && el.hasAttribute("href")) return "link";
    if (el instanceof HTMLInputElement) {
      if (["button", "submit", "reset", "image"].includes(el.type)) return "button";
      if (el.type === "checkbox" || el.type === "radio") return el.type;
      return ["text", "search", "email", "password", "tel", "url"].includes(el.type) ? "textbox" : "";
    }
    if (tag === "textarea") return "textbox";
    if (tag === "select") return "combobox";
    return "";
  };
  let entry: Entry | undefined;
  let resolvedToken = token;
  if (token) {
    entry = state.entries[token];
    if (entry?.document !== document || entry.url !== location.href || !entry.element.isConnected) return fail("STALE_TARGET");
  } else {
    let matches: Element[];
    try {
      if ("x" in target) {
        if (target.x < 0 || target.y < 0 || target.x >= innerWidth || target.y >= innerHeight) return fail("TARGET_OUTSIDE_VIEWPORT");
        const el = document.elementFromPoint(target.x, target.y);
        matches = el ? [el] : [];
      } else {
        matches = [];
        const walker = document.createTreeWalker(document.documentElement, 1);
        let visits = 0;
        for (let node: Node | null = walker.currentNode; node; node = walker.nextNode()) {
          if (++visits > 5000) { budget.limited = true; break; }
          const el = node as Element;
          let candidate = false;
          if ("selector" in target) candidate = el.matches(target.selector);
          else if ("role" in target) candidate = role(el) === target.role;
          else candidate = el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement || el instanceof HTMLSelectElement;
          if (!candidate || !eligible(el)) continue;
          if ("selector" in target || accessibleName(el) === normalized("role" in target ? target.name : target.label)) matches.push(el);
          if (matches.length > 1) return fail("AMBIGUOUS_TARGET");
          if (isLimited()) break;
        }
      }
    } catch { return fail("INVALID_TARGET"); }
    if (isLimited()) return fail("TARGET_QUERY_LIMIT");
    if (matches.length !== 1) return fail(matches.length ? "AMBIGUOUS_TARGET" : "TARGET_NOT_FOUND");
    const element = matches[0];
    if (!element || !eligible(element)) return fail("TARGET_NOT_INTERACTABLE");
    const r = element.getBoundingClientRect();
    const box = visibleBox(element);
    if (!box || isLimited()) return fail(isLimited() ? "TARGET_QUERY_LIMIT" : "TARGET_NOT_INTERACTABLE");
    entry = { element, document, inputType: element instanceof HTMLInputElement ? element.type : undefined, readOnly: element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement ? element.readOnly : undefined, rectX: r.x, rectY: r.y, rectWidth: r.width, rectHeight: r.height, x: "x" in target ? target.x : box.x + box.width / 2, y: "y" in target ? target.y : box.y + box.height / 2, width: box.width, height: box.height, coordinate: "x" in target, url: location.href, viewportWidth: innerWidth, viewportHeight: innerHeight };
    resolvedToken = state.documentId + ":t" + String(++state.next);
    // Each action owns only its latest target, bounding ephemeral retention.
    state.entries = { [resolvedToken]: entry };
  }
  if (entry.viewportWidth !== innerWidth || entry.viewportHeight !== innerHeight) return fail("VIEWPORT_CHANGED");
  if (!eligible(entry.element)) return fail("TARGET_NOT_INTERACTABLE");
  const unchangedGeometry = (): boolean => {
    if ((entry.element instanceof HTMLInputElement && entry.element.type !== entry.inputType) ||
        ((entry.element instanceof HTMLInputElement || entry.element instanceof HTMLTextAreaElement) && entry.element.readOnly !== entry.readOnly)) return false;
    const r = entry.element.getBoundingClientRect();
    const box = visibleBox(entry.element);
    if (!box || Math.abs(box.width - entry.width) > 0.5 || Math.abs(box.height - entry.height) > 0.5 ||
        (!entry.coordinate && (Math.abs(box.x + box.width / 2 - entry.x) > 0.5 || Math.abs(box.y + box.height / 2 - entry.y) > 0.5))) return false;
    return Math.abs(r.x - entry.rectX) <= 0.5 && Math.abs(r.y - entry.rectY) <= 0.5 &&
      Math.abs(r.width - entry.rectWidth) <= 0.5 && Math.abs(r.height - entry.rectHeight) <= 0.5;
  };
  if (!unchangedGeometry()) return fail("TARGET_MOVED");
  if (isLimited()) return fail("TARGET_QUERY_LIMIT");
  if (entry.x < 0 || entry.y < 0 || entry.x >= innerWidth || entry.y >= innerHeight) return fail("TARGET_OUTSIDE_VIEWPORT");
  const hit = document.elementFromPoint(entry.x, entry.y);
  if (!hit || (hit !== entry.element && !entry.element.contains(hit))) return fail("TARGET_OBSCURED");
  const unchanged = (): boolean => entry.element.isConnected && hit.isConnected && entry.document === document &&
    entry.url === location.href && innerWidth === entry.viewportWidth && innerHeight === entry.viewportHeight &&
    eligible(entry.element) && !isLimited() && unchangedGeometry() && document.elementFromPoint(entry.x, entry.y) === hit;
  if (observe && (dispatch || edit)) return fail("INVALID_TARGET_OPERATION");
  if (edit) {
    const el = entry.element;
    if (!(el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) || el.readOnly || el.disabled ||
        (el instanceof HTMLInputElement && !["text", "search", "tel", "url", "email", "password"].includes(el.type))) return fail("TARGET_NOT_EDITABLE");
    el.focus();
    if (!unchanged()) return { ok: false, error: "INPUT_UNCERTAIN", mayHaveCompleted: true };
    try {
      const proto = el instanceof HTMLInputElement ? HTMLInputElement.prototype : HTMLTextAreaElement.prototype;
      const descriptor = Object.getOwnPropertyDescriptor(proto, "value");
      if (!descriptor?.set) return { ok: false, error: "INPUT_UNCERTAIN", mayHaveCompleted: true };
      descriptor.set.call(el, edit.action === "fill" ? edit.text : el.value + edit.text);
      el.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: edit.text }));
    } catch { return { ok: false, error: "INPUT_UNCERTAIN", mayHaveCompleted: true }; }
  }
  if (dispatch) {
    // Do not retry this event sequence: handlers may mutate synchronously after pointerdown.
    const options = { bubbles: true, cancelable: true, clientX: entry.x, clientY: entry.y, button: 0 };
    try {
      hit.dispatchEvent(new PointerEvent("pointerdown", { ...options, pointerId: 1, pointerType: "mouse", isPrimary: true, buttons: 1 }));
      if (!unchanged()) return { ok: false, error: "INPUT_UNCERTAIN", mayHaveCompleted: true };
      hit.dispatchEvent(new MouseEvent("mousedown", { ...options, buttons: 1 }));
      if (!unchanged()) return { ok: false, error: "INPUT_UNCERTAIN", mayHaveCompleted: true };
      hit.dispatchEvent(new PointerEvent("pointerup", { ...options, pointerId: 1, pointerType: "mouse", isPrimary: true, buttons: 0 }));
      if (!unchanged()) return { ok: false, error: "INPUT_UNCERTAIN", mayHaveCompleted: true };
      hit.dispatchEvent(new MouseEvent("mouseup", { ...options, buttons: 0 }));
      if (!unchanged()) return { ok: false, error: "INPUT_UNCERTAIN", mayHaveCompleted: true };
      hit.dispatchEvent(new MouseEvent("click", { ...options, buttons: 0 }));
    } catch { return { ok: false, error: "INPUT_UNCERTAIN", mayHaveCompleted: true }; }
  }
  return { ok: true, token: resolvedToken, documentId: state.documentId, x: entry.x, y: entry.y, width: entry.width, height: entry.height, visible: true, enabled: enabled(entry.element), editable: editable(entry.element), focused: document.activeElement === entry.element, sensitive: entry.element instanceof HTMLInputElement && (entry.element.type === "password" || /^(current|new)-password$/.test(entry.element.autocomplete)), viewportWidth: innerWidth, viewportHeight: innerHeight, ...((dispatch || edit) ? { inputGuarantee: "synthetic-coordinate" as const, mayHaveCompleted: true } : {}) };
}
