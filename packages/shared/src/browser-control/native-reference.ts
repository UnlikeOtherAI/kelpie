/** Ephemeral reference data, not a content script. Replaced by the next snapshot and lost on navigation. */
export function rememberNativeSnapshot(collected: { snapshot: unknown; targets: Record<string, Element> }): unknown {
  Object.defineProperty(window, "__kelpieBrowserControlRefs", {
    configurable: true, writable: true, value: { targets: collected.targets, url: location.href },
  });
  return collected.snapshot;
}

/** Verify original object identity; identical replacement nodes must not inherit a reference. */
export function resolveNativeReference(ref: string): { selector?: string; error?: string } {
  const state = (window as Window & {
    __kelpieBrowserControlRefs?: { targets: Record<string, Element>; url: string };
  }).__kelpieBrowserControlRefs;
  const el = state?.targets[ref];
  if (!el?.isConnected || state?.url !== location.href) return { error: "STALE_REFERENCE" };
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
