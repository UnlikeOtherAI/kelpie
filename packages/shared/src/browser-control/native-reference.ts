/** Ephemeral reference data, not a content script. Replaced by the next snapshot and lost on navigation. */
export function rememberNativeSnapshot(collected: { snapshot: unknown; targets: Record<string, Element> }, key = "__kelpieBrowserControlRefs"): unknown {
  Object.defineProperty(window, key, {
    configurable: true, writable: true, value: { targets: collected.targets, url: location.href },
  });
  return collected.snapshot;
}

/** Verify original object identity; identical replacement nodes must not inherit a reference. */
export function resolveNativeReference(ref: string, key = "__kelpieBrowserControlRefs"): { selector?: string; error?: string } {
  const state = (window as unknown as Record<string, { targets: Record<string, Element>; url: string } | undefined>)[key];
  const el = state?.targets[ref];
  if (!state || !el?.isConnected || state.url !== location.href) return { error: "STALE_REFERENCE" };
  if (!(el.getRootNode() instanceof Document)) return { error: "UNSUPPORTED" };
  const parts: string[] = [];
  for (let node: Element | null = el; node; node = node.parentElement) {
    const parent: Element | null = node.parentElement;
    const index = parent ? Array.from(parent.children).indexOf(node) + 1 : 1;
    parts.unshift(`${node.tagName.toLowerCase()}:nth-child(${String(index)})`);
  }
  const selector = parts.join(" > ");
  const matches = document.querySelectorAll(selector);
  if (matches.length !== 1 || matches[0] !== el) return { error: "STALE_REFERENCE" };
  return { selector };
}

/** Atomic DOM activation/append on the captured object. Fixed internal script, never caller JavaScript. */
export function actOnNativeReference(ref: string, key: string, method: "tab.click" | "tab.type", text = ""): { ok?: true; error?: string; mayHaveCompleted?: boolean } {
  const state = (window as unknown as Record<string, { targets: Record<string, Element>; url: string } | undefined>)[key];
  const el = state?.targets[ref];
  if (!state || !el?.isConnected || state.url !== location.href) return { error: "STALE_REFERENCE", mayHaveCompleted: false };
  if (!(el instanceof HTMLElement) || !(el.getRootNode() instanceof Document)) return { error: "UNSUPPORTED", mayHaveCompleted: false };
  if (method === "tab.type" && !(el instanceof HTMLInputElement) && !(el instanceof HTMLTextAreaElement) && !el.isContentEditable) return { error: "UNSUPPORTED", mayHaveCompleted: false };
  if (method === "tab.type" && el instanceof HTMLInputElement && !["text", "search", "tel", "url", "email", "password"].includes(el.type)) return { error: "UNSUPPORTED", mayHaveCompleted: false };
  if ((el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) && (el.disabled || el.readOnly)) return { error: "UNSUPPORTED", mayHaveCompleted: false };
  // Focus may synchronously invoke page handlers, so verify again immediately before the mutation.
  el.focus();
  // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition -- focus handlers can detach the node synchronously.
  if (!el.isConnected || state.url !== location.href) return { error: "STALE_REFERENCE", mayHaveCompleted: true };
  if (method === "tab.type" && ((el instanceof HTMLInputElement && !["text", "search", "tel", "url", "email", "password"].includes(el.type)) ||
    ((el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) && (el.disabled || el.readOnly)) ||
    (!(el instanceof HTMLInputElement) && !(el instanceof HTMLTextAreaElement) && !el.isContentEditable))) return { error: "UNSUPPORTED", mayHaveCompleted: true };
  if (method === "tab.click") el.click();
  else if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) {
    const prototype = el instanceof HTMLInputElement ? HTMLInputElement.prototype : HTMLTextAreaElement.prototype;
    const value = Object.getOwnPropertyDescriptor(prototype, "value");
    if (!value?.get || !value.set) return { error: "UNSUPPORTED", mayHaveCompleted: true };
    value.set.call(el, String(value.get.call(el)) + text);
    el.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: text }));
  } else {
    el.append(document.createTextNode(text));
    el.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: text }));
  }
  return { ok: true };
}
