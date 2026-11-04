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
}

/**
 * Fixed ephemeral reader for a private renderer world. Self-contained for native generation.
 * Resolution stores object identity; preflight never silently retargets after animation.
 * Optional dispatch is atomic synthetic coordinate input, never advertised as trusted input.
 */
export function resolveScriptTarget(target: ScriptTarget, key: string, token?: string, dispatch = false, edit?: { action: "fill" | "type"; text: string }, observe = false): ScriptTargetResult {
  interface Entry { element: Element; document: Document; x: number; y: number; width: number; height: number; coordinate: boolean; url: string; viewportWidth: number; viewportHeight: number };
  interface State { document: Document; documentId: string; next: number; entries: Record<string, Entry> };
  const registry = window as unknown as Record<string, State | undefined>;
  let state = registry[key];
  if (state?.document !== document) {
    state = { document, documentId: String(Date.now()) + "-" + Math.random().toString(36).slice(2), next: 0, entries: Object.create(null) as Record<string, Entry> };
    Object.defineProperty(window, key, { configurable: true, value: state });
  }
  const fail = (error: string): ScriptTargetResult => ({ ok: false, error, mayHaveCompleted: false });
  if ((dispatch && edit) || (observe && (dispatch || edit))) return fail("INVALID_TARGET_OPERATION");
  const normalized = (s: string): string => s.replace(/\s+/g, " ").trim();
  const visible = (el: Element): boolean => {
    const r = el.getBoundingClientRect();
    for (let parent: Element | null = el; parent; parent = parent.parentElement) {
      const inherited = getComputedStyle(parent);
      if (inherited.visibility !== "visible" || inherited.display === "none" || Number(inherited.opacity) === 0) return false;
    }
    const style = getComputedStyle(el);
    return el.isConnected && r.width > 0 && r.height > 0 && style.display !== "none" && style.visibility === "visible" && Number(style.opacity) > 0;
  };
  const enabled = (el: Element): boolean => !el.matches(":disabled") && !el.closest('[inert],[aria-disabled="true"]') && !(el instanceof HTMLButtonElement && el.disabled) && !(el instanceof HTMLInputElement && el.disabled) && !(el instanceof HTMLTextAreaElement && el.disabled) && !(el instanceof HTMLSelectElement && el.disabled);
  const eligible = (el: Element): boolean => visible(el) && (observe || enabled(el));
  const accessibleName = (el: Element): string => {
    const labelledBy = el.getAttribute("aria-labelledby");
    if (labelledBy) return normalized(labelledBy.split(/\s+/).map(id => document.getElementById(id)?.textContent ?? "").join(" "));
    const aria = el.getAttribute("aria-label");
    if (aria !== null) return normalized(aria);
    if (el instanceof HTMLInputElement && ["button", "submit", "reset"].includes(el.type)) return normalized(el.value.length ? el.value : (el.type === "submit" ? "Submit" : el.type === "reset" ? "Reset" : ""));
    if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement || el instanceof HTMLSelectElement) {
      // Inputs such as image buttons may have no label collection.
      const labels = Array.from(el.labels ?? []).map(label => label.textContent).join(" ");
      return normalized(labels.length ? labels : (el.getAttribute("alt") ?? el.getAttribute("title") ?? ""));
    }
    return normalized(el.textContent);
  };
  const role = (el: Element): string => {
    const explicit = el.getAttribute("role");
    if (explicit) return explicit.split(/\s+/)[0] ?? "";
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
      } else if ("selector" in target) {
        matches = Array.from(document.querySelectorAll(target.selector)).filter(eligible);
      } else {
        matches = Array.from(document.querySelectorAll("*")).filter(el => {
          if (!eligible(el)) return false;
          if ("role" in target) return role(el) === target.role && accessibleName(el) === normalized(target.name);
          if (!(el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement || el instanceof HTMLSelectElement)) return false;
          return accessibleName(el) === normalized(target.label);
        });
      }
    } catch { return fail("INVALID_TARGET"); }
    if (matches.length !== 1) return fail(matches.length ? "AMBIGUOUS_TARGET" : "TARGET_NOT_FOUND");
    const element = matches[0];
    if (!element || !eligible(element)) return fail("TARGET_NOT_INTERACTABLE");
    const r = element.getBoundingClientRect();
    entry = { element, document, x: "x" in target ? target.x : r.x + r.width / 2, y: "y" in target ? target.y : r.y + r.height / 2, width: r.width, height: r.height, coordinate: "x" in target, url: location.href, viewportWidth: innerWidth, viewportHeight: innerHeight };
    resolvedToken = "t" + String(++state.next);
    // Each action owns only its latest target, bounding ephemeral retention.
    state.entries = { [resolvedToken]: entry };
  }
  if (entry.viewportWidth !== innerWidth || entry.viewportHeight !== innerHeight) return fail("VIEWPORT_CHANGED");
  if (!eligible(entry.element)) return fail("TARGET_NOT_INTERACTABLE");
  const r = entry.element.getBoundingClientRect();
  if (!entry.coordinate && (Math.abs(r.x + r.width / 2 - entry.x) > 0.5 || Math.abs(r.y + r.height / 2 - entry.y) > 0.5 || Math.abs(r.width - entry.width) > 0.5 || Math.abs(r.height - entry.height) > 0.5)) return fail("TARGET_MOVED");
  if (entry.x < 0 || entry.y < 0 || entry.x >= innerWidth || entry.y >= innerHeight) return fail("TARGET_OUTSIDE_VIEWPORT");
  const hit = document.elementFromPoint(entry.x, entry.y);
  if (!hit || (hit !== entry.element && !entry.element.contains(hit))) return fail("TARGET_OBSCURED");
  if (observe && (dispatch || edit)) return fail("INVALID_TARGET_OPERATION");
  if (edit) {
    const el = entry.element;
    if (!(el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) || el.readOnly || el.disabled ||
        (el instanceof HTMLInputElement && !["text", "search", "tel", "url", "email", "password"].includes(el.type))) return fail("TARGET_NOT_EDITABLE");
    el.focus();
    if (!el.isConnected || state.document !== document || state.entries[resolvedToken ?? ""] !== entry || !eligible(el)) return { ok: false, error: "INPUT_UNCERTAIN", mayHaveCompleted: true };
    const r2 = el.getBoundingClientRect();
    const h2 = document.elementFromPoint(entry.x, entry.y);
    if (Math.abs(r2.x + r2.width / 2 - entry.x) > 0.5 || Math.abs(r2.y + r2.height / 2 - entry.y) > 0.5 ||
        (h2 !== el && !el.contains(h2))) return { ok: false, error: "INPUT_UNCERTAIN", mayHaveCompleted: true };
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
      const unchanged = (): boolean => {
        const current = entry.element.getBoundingClientRect();
        const top = document.elementFromPoint(entry.x, entry.y);
        return entry.element.isConnected && entry.url === location.href && innerWidth === entry.viewportWidth && innerHeight === entry.viewportHeight &&
          eligible(entry.element) && (top === entry.element || (top !== null && entry.element.contains(top))) &&
          (entry.coordinate || (Math.abs(current.x + current.width / 2 - entry.x) <= 0.5 && Math.abs(current.y + current.height / 2 - entry.y) <= 0.5));
      };
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
  return { ok: true, token: resolvedToken, documentId: state.documentId, x: entry.x, y: entry.y, width: entry.width, height: entry.height, visible: true, enabled: enabled(entry.element), viewportWidth: innerWidth, viewportHeight: innerHeight, ...((dispatch || edit) ? { inputGuarantee: "synthetic-coordinate" as const, mayHaveCompleted: true } : {}) };
}
