import { BrowserControlError } from "./protocol.js";
import type { BrowserControlBackend, BrowserControlMethod, BrowserControlRequest, BrowserElement, BrowserSnapshot } from "./protocol.js";

/** A product supplies authorized operations. Unimplemented operations are never advertised or approximated. */
export type BrowserOperations = {
  [M in BrowserControlMethod]?: (request: Extract<BrowserControlRequest, { method: M }>) => Promise<unknown>;
};

export function createBrowserBackend(operations: BrowserOperations, extensions: string[] = []): BrowserControlBackend {
  return {
    capabilities: { version: 1, methods: ["capabilities", "documentation", ...Object.keys(operations) as BrowserControlMethod[]], extensions },
    execute(request) {
      const operation = operations[request.method] as ((request: BrowserControlRequest) => Promise<unknown>) | undefined;
      if (!operation) throw new BrowserControlError("UNSUPPORTED", `This browser does not implement ${request.method}.`);
      return operation(request);
    },
  };
}

/** Values never enter the common snapshot; product scrubbing happens before this bound. */
export function browserSnapshot(
  input: { url: string; title: string; elements: BrowserElement[]; truncated?: boolean },
  limits: { maxElements?: number; maxChars?: number } = {},
): BrowserSnapshot {
  const maxChars = limits.maxChars ?? 16_000;
  const elements: BrowserElement[] = [];
  const url = input.url.slice(0, Math.min(4096, Math.floor(maxChars / 2)));
  const title = input.title.replace(/\s+/g, " ").trim().slice(0, Math.min(1024, Math.floor(maxChars / 4)));
  let text = `url: ${url}\ntitle: ${title}`;
  for (const el of input.elements.slice(0, limits.maxElements ?? 200)) {
    const element = { ref: el.ref, role: el.role.slice(0, 80), name: el.name.replace(/\s+/g, " ").trim().slice(0, 256) };
    const line = `\n[${element.ref}] ${element.role} ${JSON.stringify(element.name)}`;
    if (text.length + line.length > maxChars) break;
    text += line;
    elements.push(element);
  }
  return { url, title, text, elements, truncated: input.truncated === true || elements.length < input.elements.length || url !== input.url || title !== input.title };
}
