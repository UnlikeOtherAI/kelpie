import { z } from "zod";
import { BrowserControlError, browserControlMutates } from "../../src/browser-control/protocol.js";
import type { BrowserControlBackend, BrowserControlRequest, BrowserTabInfo } from "../../src/browser-control/protocol.js";
import { createBrowserBackend } from "../../src/browser-control/reference.js";
import { collectBrowserSnapshot } from "../../src/browser-control/snapshot.js";
import { rememberNativeSnapshot, resolveNativeReference } from "../../src/browser-control/native-reference.js";
import type { BrowserSnapshot } from "../../src/browser-control/protocol.js";
import type { BrowserOperations } from "../../src/browser-control/reference.js";

export interface KelpieBrowserBinding {
  /** Already authenticated and scoped to a device/allocation. Must not retry a dispatched mutation. */
  call(method: string, params: Record<string, unknown>): Promise<unknown>;
  /** The device's advertised methods, in native camelCase. */
  methods: ReadonlySet<string>;
  /** Mobile handlers use the selected tab; select it explicitly before every tab operation. */
  targeting?: "direct" | "selected";
}
const response = z.object({ success: z.boolean().optional(), error: z.unknown().optional() }).loose();
const tab = z.object({ id: z.string(), url: z.string().optional(), title: z.string().optional() });
/** Native HTTP and device-socket routes share this adapter; authentication belongs to the caller. */
export function createKelpieBrowserBackend(binding: KelpieBrowserBinding): BrowserControlBackend {
  const refs = new Map<string, Set<string>>();
  const session = globalThis.crypto.randomUUID();
  let generation = 0;
  const call = async (method: string, params: Record<string, unknown> = {}): Promise<Record<string, unknown>> => {
    const parsed = response.safeParse(await binding.call(method, params));
    if (!parsed.success || parsed.data.success === false || parsed.data.error) {
      throw new Error("Native browser command did not succeed.");
    }
    return parsed.data;
  };
  const current = async (id: string) => {
    const result = await call("getCurrentUrl", { tabId: id });
    return { url: typeof result.url === "string" ? result.url : "", title: typeof result.title === "string" ? result.title : "" };
  };
  const evaluate = async (id: string, expression: string): Promise<unknown> => (await call("evaluate", { tabId: id, expression })).result;
  const act = async (request: Extract<BrowserControlRequest, { method: "tab.click" | "tab.type" }>) => {
    const id = request.tabId ?? "";
    if (!refs.get(id)?.has(request.params.ref)) throw new BrowserControlError("STALE_REFERENCE", "Observe this tab again before acting.");
    const target = z.object({ selector: z.string().optional(), error: z.string().optional() }).parse(
      await evaluate(id, `(${resolveNativeReference.toString()})(${JSON.stringify(request.params.ref)})`),
    );
    if (!target.selector) throw new BrowserControlError(target.error ?? "STALE_REFERENCE", "Observe this tab again before acting.");
    await call(request.method === "tab.click" ? "click" : "type", {
      tabId: id, selector: target.selector, ...(request.method === "tab.type" ? { text: request.params.text } : {}),
    });
    return null;
  };
  const operations: BrowserOperations = {};
  const has = (...methods: string[]) => methods.every((method) => binding.methods.has(method));
  if (has("getTabs")) operations["tabs.list"] = async () => z.array(tab).parse((await call("getTabs")).tabs);
  if (has("newTab")) operations["tabs.new"] = async (request): Promise<BrowserTabInfo> => {
    const result = await call("newTab", request.params);
    return tab.parse(result.tab ?? { id: result.tabId, url: request.params.url });
  };
  if (has("closeTab")) operations["tabs.close"] = async (request) => { await call("closeTab", { tabId: request.tabId }); return null; };
  if (has("getCurrentUrl")) {
    operations["tab.url"] = async (request) => (await current(request.tabId ?? "")).url;
    operations["tab.title"] = async (request) => (await current(request.tabId ?? "")).title;
  }
  if (has("evaluate")) {
    operations["tab.snapshot"] = async (request) => {
      const id = request.tabId ?? "";
      refs.delete(id);
      const options = { ...request.params, prefix: `${session}s${String(++generation)}e`, includeShadow: false };
      const value = await evaluate(id, `(${rememberNativeSnapshot.toString()})((${collectBrowserSnapshot.toString()})(${JSON.stringify(options)}))`);
      const snapshot = z.object({
        url: z.string(), title: z.string(), text: z.string(), truncated: z.boolean(),
        elements: z.array(z.object({ ref: z.string(), role: z.string(), name: z.string() })),
      }).parse(value) satisfies BrowserSnapshot;
      refs.set(id, new Set(snapshot.elements.map((element) => element.ref)));
      return snapshot;
    };
    if (has("click")) operations["tab.click"] = act;
    if (has("type")) operations["tab.type"] = act;
  }
  if (has("switchTab")) operations["tabs.select"] = async (request) => { await call("switchTab", { tabId: request.tabId }); return null; };
  if (has("navigate")) operations["tab.goto"] = async (request) => { await call("navigate", { tabId: request.tabId, url: request.params.url }); return null; };
  for (const method of ["back", "forward", "reload"] as const) {
    if (has(method)) operations[`tab.${method}`] = async (request) => { await call(method, { tabId: request.tabId }); return null; };
  }
  if (has("pressKey")) operations["page.press"] = async (request) => { await call("pressKey", { tabId: request.tabId, key: request.params.key }); return null; };
  if (has("scroll")) operations["page.scroll"] = async (request) => { await call("scroll", { tabId: request.tabId, ...request.params }); return null; };
  if (has("screenshot")) operations["tab.screenshot"] = async (request) => {
    const result = await call("screenshot", { tabId: request.tabId, resolution: "viewport", ...request.params });
    if (typeof result.image !== "string") throw new Error("Missing screenshot.");
    return { type: "image", mimeType: result.format === "jpeg" ? "image/jpeg" : "image/png", data: result.image };
  };
  const backend = createBrowserBackend(operations, ["kelpie"]);
  return { capabilities: backend.capabilities, async execute(request) {
    try {
      if (request.tabId && binding.targeting === "selected" && request.method !== "tabs.close" && request.method !== "tabs.select") {
        if (!has("switchTab")) throw new BrowserControlError("UNSUPPORTED", "This browser cannot select the requested tab.");
        await call("switchTab", { tabId: request.tabId });
      }
      return await backend.execute(request);
    }
    finally { if (request.tabId && browserControlMutates(request.method)) refs.delete(request.tabId); }
  } };
}
