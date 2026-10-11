import { z } from "zod";

const text = z.string().max(65_536);
const matcher = z.union([z.string().max(4096), z.object({ source: z.string().max(4096), flags: z.string().max(8) }).strict()]);
const query = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("role"), role: z.string().min(1).max(80), name: matcher.optional(), exact: z.boolean().optional() }).strict(),
  z.object({ kind: z.enum(["label", "text", "placeholder", "testId", "css", "frame"]), value: matcher, exact: z.boolean().optional() }).strict(),
  z.object({ kind: z.literal("nth"), index: z.number().int().min(-1).max(100_000) }).strict(),
  z.object({ kind: z.literal("filter"), hasText: matcher.optional(), visible: z.boolean().optional() }).strict(),
]);
export const BrowserLocatorSchema = z.array(query).min(1).max(16);
export type BrowserLocator = z.infer<typeof BrowserLocatorSchema>;
export type BrowserTextMatcher = z.infer<typeof matcher>;
const timeoutMs = z.number().int().min(0).max(120_000).optional();
const tabId = z.string().min(1).max(256);
const locator = { locator: BrowserLocatorSchema, timeoutMs };
const selection = z.union([text, z.object({ value: text.optional(), label: text.optional(), index: z.number().int().nonnegative().optional() }).strict()]);
const request = <M extends string, S extends z.ZodType>(method: M, params: S) => z.object({
  version: z.literal(1), method: z.literal(method), tabId: tabId.optional(), params,
}).strict();
const empty = z.object({}).strict().default({});
export const BrowserControlRequestSchema = z.discriminatedUnion("method", [
  request("capabilities", empty), request("documentation", empty), request("tabs.list", empty),
  request("tabs.new", z.object({ url: z.string().max(8192).optional() }).strict().default({})),
  request("tabs.close", empty), request("tabs.select", empty),
  request("tab.goto", z.object({ url: z.string().min(1).max(8192), timeoutMs }).strict()),
  request("tab.back", z.object({ timeoutMs }).strict().default({})),
  request("tab.forward", z.object({ timeoutMs }).strict().default({})),
  request("tab.reload", z.object({ timeoutMs }).strict().default({})),
  request("tab.url", empty), request("tab.title", empty),
  request("tab.click", z.object({ ref: z.string().min(1).max(1024) }).strict()),
  request("tab.type", z.object({ ref: z.string().min(1).max(1024), text }).strict()),
  request("tab.snapshot", z.object({ maxElements: z.number().int().min(1).max(1000).optional(), maxChars: z.number().int().min(256).max(100_000).optional() }).strict().default({})),
  request("tab.screenshot", z.object({ fullPage: z.boolean().optional(), format: z.enum(["png", "jpeg"]).optional(), quality: z.number().int().min(0).max(100).optional() }).strict().default({})),
  request("locator.click", z.object({ ...locator, button: z.enum(["left", "right", "middle"]).optional(), modifiers: z.array(z.enum(["Alt", "Control", "ControlOrMeta", "Meta", "Shift"])).max(5).optional() }).strict()),
  request("locator.dblclick", z.object(locator).strict()),
  request("locator.fill", z.object({ ...locator, value: text }).strict()),
  request("locator.type", z.object({ ...locator, text }).strict()),
  request("locator.press", z.object({ ...locator, key: z.string().min(1).max(100) }).strict()),
  request("locator.check", z.object(locator).strict()), request("locator.uncheck", z.object(locator).strict()),
  request("locator.selectOption", z.object({ ...locator, value: z.union([selection, z.array(selection).max(100)]) }).strict()),
  request("locator.innerText", z.object(locator).strict()), request("locator.textContent", z.object(locator).strict()),
  request("locator.getAttribute", z.object({ ...locator, name: z.string().min(1).max(256) }).strict()),
  request("locator.count", z.object(locator).strict()), request("locator.isVisible", z.object(locator).strict()),
  request("locator.isEnabled", z.object(locator).strict()),
  request("locator.waitFor", z.object({ ...locator, state: z.enum(["attached", "detached", "visible", "hidden"]).optional() }).strict()),
  request("page.press", z.object({ key: z.string().min(1).max(100) }).strict()),
  request("page.scroll", z.object({ deltaX: z.number().min(-100_000).max(100_000).default(0), deltaY: z.number().min(-100_000).max(100_000) }).strict()),
]);
export type BrowserControlRequest = z.infer<typeof BrowserControlRequestSchema>;
export type BrowserControlMethod = BrowserControlRequest["method"];
export interface BrowserTabInfo { id: string; url?: string; title?: string }
export interface BrowserElement { ref: string; role: string; name: string }
export interface BrowserSnapshot { url: string; title: string; text: string; truncated: boolean; elements?: BrowserElement[] }
export interface BrowserImage { type: "image"; mimeType: "image/png" | "image/jpeg"; data: string }
export interface BrowserCapabilities { version: 1; methods: BrowserControlMethod[]; extensions: string[] }
export interface BrowserControlFailure { code: string; message: string; mayHaveCompleted: boolean }
export type BrowserControlResponse = { version: 1; ok: true; value: unknown } | { version: 1; ok: false; error: BrowserControlFailure };
export interface BrowserControlTransport { call(request: BrowserControlRequest): Promise<BrowserControlResponse> }
export interface BrowserControlBackend {
  capabilities: BrowserCapabilities;
  execute(request: BrowserControlRequest): Promise<unknown>;
}
export class BrowserControlError extends Error {
  constructor(readonly code: string, message: string, readonly mayHaveCompleted = false) { super(message); this.name = "BrowserControlError"; }
}
export const BROWSER_CONTROL_METHODS: BrowserControlMethod[] = BrowserControlRequestSchema.options.map((option) => option.shape.method.value);
const reads = new Set<BrowserControlMethod>(["capabilities", "documentation", "tabs.list", "tab.url", "tab.title", "tab.snapshot", "tab.screenshot", "locator.innerText", "locator.textContent", "locator.getAttribute", "locator.count", "locator.isVisible", "locator.isEnabled", "locator.waitFor"]);
export const browserControlMutates = (method: BrowserControlMethod): boolean => !reads.has(method);
/** Same JSON schema is used by every MCP/model wrapper; no product-maintained copy. */
export const BrowserControlEnvelopeSchema = z.object({ request: BrowserControlRequestSchema }).strict();
export function browserControlRequestSchema(options: { methods?: readonly BrowserControlMethod[]; compact?: boolean } = {}) {
  const allowed = options.methods ? new Set(options.methods) : undefined;
  const variants = BrowserControlRequestSchema.options.filter((option) => !allowed || allowed.has(option.shape.method.value));
  if (!variants.length) throw new Error("At least one browser method must be included in the input schema.");
  if (options.compact) {
    const shape = BrowserControlRequestSchema.options[0].shape;
    return z.object({
      version: shape.version, method: z.enum(variants.map((option) => option.shape.method.value)),
      tabId: shape.tabId,
      params: z.looseObject({}).default({}).describe("Call documentation once for method parameters; every call is validated against the strict v1 contract."),
    }).strict();
  }
  return options.methods ? z.union(variants) : BrowserControlRequestSchema;
}
export function browserControlInputSchema(options: { methods?: readonly BrowserControlMethod[]; compact?: boolean } = {}): Record<string, unknown> {
  return z.toJSONSchema(z.object({ request: browserControlRequestSchema(options) }).strict(), { reused: "ref" });
}
