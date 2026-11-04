import { BrowserControlError } from "./protocol.js";
import { boundedWebMcpJson } from "./webmcp-json.js";
import { webMcpCallParamsSchema, webMcpDiscoverParamsSchema, webMcpDiscoverySchema } from "./webmcp-schema.js";
import type { WebMcpCallParams, WebMcpDiscoverParams, WebMcpDiscovery, WebMcpIdentity } from "./webmcp-schema.js";
import type { WebMcpPageInput } from "./webmcp-reader.js";

export interface WebMcpBinding {
  /** Exact supported runtime API, selected by the trusted host, never page hints. */
  inputEncoding: "json-string" | "object";
  /** Existing authenticated session, exact current origin and renderer generation. */
  identity(): Promise<WebMcpIdentity>;
  /** Explicit host grant. A page hint never grants discovery or invocation. */
  authorize(identity: WebMcpIdentity, operation: "discover" | "call"): Promise<void> | void;
  /** Executes webMcpPageExpression only in this owned document. */
  evaluate(input: WebMcpPageInput): Promise<unknown>;
}
export interface WebMcpController {
  probe(origin: string): Promise<{ available: boolean; [key: string]: unknown }>;
  discover(params: WebMcpDiscoverParams): Promise<WebMcpDiscovery>;
  call(params: WebMcpCallParams): Promise<unknown>;
  dispose(): Promise<void>;
}
const equal = (left: WebMcpIdentity, right: WebMcpIdentity): boolean =>
  left.sessionId === right.sessionId && left.origin === right.origin && left.documentGeneration === right.documentGeneration;

/** Policy and completion ownership surround the fixed browser API operation. */
export function createWebMcpController(binding: WebMcpBinding): WebMcpController {
  if (!["json-string", "object"].includes(binding.inputEncoding)) throw new BrowserControlError("INVALID_ARGUMENTS", "Choose an audited site tool input encoding.");
  const registryKey = "__kelpieWebMcp_" + crypto.randomUUID();
  let observed: WebMcpIdentity | undefined;
  let pending: Promise<unknown> | undefined;
  let disposed = false;
  const admit = async (origin: string, operation: "discover" | "call"): Promise<WebMcpIdentity> => {
    if (disposed) throw new BrowserControlError("SESSION_CLOSED", "The site tool session is closed.");
    if (pending) throw new BrowserControlError("BUSY", "A prior site tool operation is still pending.");
    const identity = await binding.identity();
    if (identity.origin !== origin || !identity.sessionId || !identity.documentGeneration) throw new BrowserControlError("ACCESS_DENIED", "The site tool origin or document is not authorized.");
    await binding.authorize(identity, operation);
    if (!equal(identity, await binding.identity())) throw new BrowserControlError("STALE_DOCUMENT", "The authorized document changed.");
    return identity;
  };
  const run = async (input: WebMcpPageInput, timeoutMs: number): Promise<unknown> => {
    if (pending) throw new BrowserControlError("BUSY", "A prior site tool operation is still pending.");
    const mutates = input.operation === "call";
    const operation = Promise.resolve().then(() => binding.evaluate({ ...input, inputEncoding: binding.inputEncoding }));
    pending = operation;
    void operation.finally(() => { if (pending === operation) pending = undefined; }).catch(() => undefined);
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      const raw = await Promise.race([
        operation,
        new Promise<never>((_, reject) => { timer = setTimeout(() => { reject(new BrowserControlError("TIMEOUT", "The site tool deadline elapsed; reconcile before continuing.", mutates)); }, timeoutMs); }),
      ]);
      const response = boundedWebMcpJson(raw, { maxBytes: 100_000, maxDepth: 16, maxProperties: 6000 }) as {
        ok?: boolean; value?: unknown; error?: { code?: unknown; message?: unknown; mayHaveCompleted?: unknown };
      } | null | undefined;
      if (response?.ok !== true) {
        const code = typeof response?.error?.code === "string" ? response.error.code.slice(0, 80) : "WEBMCP_FAILED";
        // Page-authored errors never become model-facing exception text.
        throw new BrowserControlError(code, "The site tool operation was refused or failed.", response?.error?.mayHaveCompleted === true);
      }
      if (!equal(input.identity, await binding.identity())) throw new BrowserControlError("STALE_DOCUMENT", "The document changed during the site tool operation.", mutates);
      try { await binding.authorize(input.identity, mutates ? "call" : "discover"); }
      catch { throw new BrowserControlError("ACCESS_DENIED", "Session permission ended during the site tool operation.", mutates); }
      return response.value;
    } catch (error) {
      if (error instanceof BrowserControlError) throw error;
      throw new BrowserControlError("WEBMCP_FAILED", "The site tool operation failed.", mutates);
    } finally { if (timer !== undefined) clearTimeout(timer); }
  };
  return {
    async probe(origin) {
      const parsed = webMcpDiscoverParamsSchema.parse({ origin });
      const identity = await admit(parsed.origin, "discover");
      const value = await run({ operation: "probe", identity, registryKey }, 10_000);
      if (!value || typeof value !== "object" || typeof (value as { available?: unknown }).available !== "boolean") throw new BrowserControlError("WEBMCP_FAILED", "The browser returned invalid site tool availability.");
      return value as { available: boolean; [key: string]: unknown };
    },
    async discover(params) {
      const parsed = webMcpDiscoverParamsSchema.parse(params);
      observed = undefined;
      const identity = await admit(parsed.origin, "discover");
      const result = webMcpDiscoverySchema.parse(await run({ operation: "discover", identity, registryKey, maxTools: parsed.maxTools, maxChars: parsed.maxChars }, 10_000));
      if (result.origin !== identity.origin || result.documentGeneration !== identity.documentGeneration) throw new BrowserControlError("STALE_DOCUMENT", "The site tool discovery belongs to a different document.");
      if (result.available) observed = identity;
      return result;
    },
    async call(params) {
      const parsed = webMcpCallParamsSchema.parse(params);
      const identity = await admit(parsed.origin, "call");
      if (!observed || !equal(observed, identity)) throw new BrowserControlError("STALE_REFERENCE", "Discover the current authorized site tools before invocation.");
      observed = undefined;
      return run({ operation: "call", identity, registryKey, ref: parsed.ref,
        input: boundedWebMcpJson(parsed.input, { maxBytes: 16_384, maxDepth: 8, maxProperties: 512, objectOnly: true }),
        timeoutMs: parsed.timeoutMs }, parsed.timeoutMs);
    },
    async dispose() {
      disposed = true;
      observed = undefined;
      // Unknown completion stays fenced; the owning session tears its renderer down.
      if (pending) return;
      const identity = await binding.identity();
      await binding.evaluate({ operation: "dispose", identity, registryKey });
    },
  };
}
