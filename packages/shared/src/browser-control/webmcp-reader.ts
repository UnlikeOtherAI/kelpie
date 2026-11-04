import { boundedWebMcpJson } from "./webmcp-json.js";
import type { WebMcpIdentity } from "./webmcp-schema.js";

export interface WebMcpPageInput {
  operation: "probe" | "discover" | "call" | "dispose";
  identity: WebMcpIdentity;
  registryKey: string;
  maxTools?: number;
  maxChars?: number;
  ref?: string;
  input?: unknown;
  timeoutMs?: number;
  inputEncoding?: "json-string" | "object";
}
interface Registered { name: string; description: string; inputSchema?: unknown; annotations?: unknown; origin: string; window: Window };
interface Context extends EventTarget {
  getTools(): Promise<Registered[]>;
  executeTool(tool: Registered, input: object | string, options: { signal: AbortSignal }): Promise<string>;
};
interface Registry {
  identity: WebMcpIdentity;
  document: Document;
  revision: number;
  targets: Map<string, { tool: Registered; name: string; fingerprint: string }>;
  cleanup(): void;
}

/** Fixed reader/action. Browser API calls are unavoidable; page metadata getters are never serialized. */
export async function runWebMcpPageOperation(options: WebMcpPageInput): Promise<unknown> {
  const failure = (code: string, message: string, mayHaveCompleted = false) =>
    ({ ok: false, error: { code, message, mayHaveCompleted } });
  const identity = options.identity;
  if (options.operation === "call" && options.inputEncoding !== "json-string" && options.inputEncoding !== "object") return failure("INVALID_ARGUMENTS", "The site tool input encoding is unsupported.");
  if (location.origin !== identity.origin) return failure("STALE_DOCUMENT", "The authorized origin changed.");
  const existing = Object.getOwnPropertyDescriptor(globalThis, options.registryKey)?.value as Registry | undefined;
  if (options.operation === "dispose") {
    existing?.cleanup();
    Reflect.deleteProperty(globalThis, options.registryKey);
    return { ok: true, value: null };
  }
  const context = (document as Document & { modelContext?: Context }).modelContext;
  if (!context || typeof context.getTools !== "function" || typeof context.executeTool !== "function") {
    return { ok: true, value: { available: false, reason: "api_unavailable", origin: identity.origin,
      documentGeneration: identity.documentGeneration, untrusted: true, tools: [], truncated: false } };
  }
  if (options.operation === "probe") return { ok: true, value: { available: true, api: "document.modelContext" } };
  const sameIdentity = (value: Registry): boolean => value.document === document &&
    value.identity.origin === identity.origin && value.identity.sessionId === identity.sessionId &&
    value.identity.documentGeneration === identity.documentGeneration;
  if (existing && !sameIdentity(existing)) existing.cleanup();
  const registry: Registry = existing && sameIdentity(existing) ? existing : (() => {
    const state: Registry = { identity, document, revision: 0, targets: new Map(), cleanup() { this.targets.clear(); } };
    const invalidate = (): void => { state.targets.clear(); state.revision++; };
    context.addEventListener("toolchange", invalidate);
    for (const event of ["pagehide", "popstate", "hashchange"]) addEventListener(event, invalidate);
    state.cleanup = () => {
      invalidate();
      context.removeEventListener("toolchange", invalidate);
      for (const event of ["pagehide", "popstate", "hashchange"]) removeEventListener(event, invalidate);
    };
    Object.defineProperty(globalThis, options.registryKey, { value: state, configurable: true });
    return state;
  })();
  const data = (item: object, key: string): unknown => {
    const descriptor = Object.getOwnPropertyDescriptor(item, key);
    if (descriptor && !("value" in descriptor)) throw new Error("Accessor metadata");
    return descriptor?.value;
  };
  const metadata = (tool: unknown): { name: string; description: string; inputSchema?: unknown; annotations?: unknown } | undefined => {
    if (!tool || typeof tool !== "object" || data(tool, "window") !== window || data(tool, "origin") !== identity.origin) return undefined;
    const name = data(tool, "name"), description = data(tool, "description");
    if (typeof name !== "string" || !name || name.length > 128 || typeof description !== "string") return undefined;
    const output: { name: string; description: string; inputSchema?: unknown; annotations?: unknown } =
      { name, description: description.slice(0, 2048) };
    for (const field of ["inputSchema", "annotations"] as const) {
      const value = data(tool, field);
      if (value !== undefined) output[field] = boundedWebMcpJson(value, { maxBytes: 8192, maxDepth: 8, maxProperties: 512 });
    }
    return output;
  };
  if (options.operation === "discover") registry.targets.clear();
  const revision = registry.revision;
  let registered: Registered[];
  try { registered = await context.getTools(); }
  catch { return failure("WEBMCP_FAILED", "The browser could not discover site tools."); }
  if (!sameIdentity(registry) || registry.revision !== revision || location.origin !== identity.origin) {
    return failure("STALE_DOCUMENT", "Observe the current document and tools again.");
  }
  if (!Array.isArray(registered) || registered.length > 1000) return failure("RESULT_LIMIT", "The site tool catalogue exceeds its limit.");
  const candidates: { tool: Registered; value: NonNullable<ReturnType<typeof metadata>>; fingerprint: string }[] = [];
  let truncated = false;
  for (let index = 0; index < registered.length; index++) {
    try {
      const descriptor = Object.getOwnPropertyDescriptor(registered, String(index));
      if (!descriptor || !("value" in descriptor)) { truncated = true; continue; }
      const tool: unknown = descriptor.value;
      const value = metadata(tool);
      if (!value) continue;
      candidates.push({ tool: tool as Registered, value, fingerprint: JSON.stringify(value) });
      if (value.description.length < String(data(tool as object, "description")).length) truncated = true;
    } catch { truncated = true; }
  }
  candidates.sort((a, b) => a.value.name.localeCompare(b.value.name));
  if (new Set(candidates.map((item) => item.value.name)).size !== candidates.length) return failure("AMBIGUOUS_TOOL", "The site exposed duplicate tool names.");
  if (options.operation === "discover") {
    const tools: unknown[] = [];
    let chars = 0;
    for (const candidate of candidates) {
      const ref = crypto.randomUUID();
      const value = { ref, ...candidate.value };
      const size = new TextEncoder().encode(JSON.stringify(value)).length;
      if (tools.length >= (options.maxTools ?? 20) || chars + size > (options.maxChars ?? 16_384)) { truncated = true; break; }
      chars += size;
      registry.targets.set(ref, { tool: candidate.tool, name: candidate.value.name, fingerprint: candidate.fingerprint });
      tools.push(value);
    }
    return { ok: true, value: { available: true, origin: identity.origin, documentGeneration: identity.documentGeneration,
      untrusted: true, tools, truncated } };
  }
  const target = registry.targets.get(options.ref ?? "");
  if (!target) return failure("STALE_REFERENCE", "Discover the current site tools before invoking one.");
  const current = candidates.find((item) => item.value.name === target.name);
  if (current?.fingerprint !== target.fingerprint) {
    registry.targets.clear();
    return failure("STALE_REFERENCE", "The observed site tool changed.");
  }
  let input: object;
  try { input = boundedWebMcpJson(options.input ?? {}, { maxBytes: 16_384, maxDepth: 8, maxProperties: 512, objectOnly: true }) as object; }
  catch { return failure("INVALID_ARGUMENTS", "Use a bounded JSON input object."); }
  registry.targets.clear(); // A tool invocation consumes this observed catalogue.
  const controller = new AbortController();
  const deadline = { timedOut: false };
  const timer = setTimeout(() => { deadline.timedOut = true; controller.abort(); }, options.timeoutMs ?? 10_000);
  try {
    const result = await context.executeTool(target.tool, options.inputEncoding === "json-string" ? JSON.stringify(input) : input, { signal: controller.signal });
    if (deadline.timedOut) return failure("TIMEOUT", "The site tool exceeded its deadline; reconcile before continuing.", true);
    if (location.origin !== identity.origin || !sameIdentity(registry)) return failure("STALE_DOCUMENT", "The document changed during site tool execution.", true);
    if (typeof result !== "string" || new TextEncoder().encode(result).length > 32_768) return failure("RESULT_LIMIT", "The site tool result exceeds its limit.", true);
    let output: unknown = result;
    let structured = false;
    try { output = JSON.parse(result); structured = true; } catch { /* Plain text is valid. */ }
    if (structured) {
      try { output = boundedWebMcpJson(output, { maxBytes: 32_768, maxDepth: 8, maxProperties: 1024 }); }
      catch { return failure("RESULT_LIMIT", "The site tool JSON exceeds its structural limit.", true); }
    }
    return { ok: true, value: { origin: identity.origin, documentGeneration: identity.documentGeneration, untrusted: true, output } };
  } catch {
    return failure(deadline.timedOut ? "TIMEOUT" : "WEBMCP_FAILED", "The site tool may have run; reconcile before continuing.", true);
  } finally { clearTimeout(timer); }
}

/** Only trusted fixed source and JSON arguments are assembled; callers supply no script. */
export function webMcpPageExpression(input: WebMcpPageInput): string {
  return `(() => { const boundedWebMcpJson = ${boundedWebMcpJson.toString()}; return (${runWebMcpPageOperation.toString()})(${JSON.stringify(input)}); })()`;
}
