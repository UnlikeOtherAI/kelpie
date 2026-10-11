import { z } from "zod";
import { BrowserControlError, browserControlMutates } from "./protocol.js";
import type { BrowserControlBackend, BrowserControlRequest, BrowserTabInfo } from "./protocol.js";
import { browserSnapshot, createBrowserBackend } from "./reference.js";
import type { BrowserOperations } from "./reference.js";

export interface KelpieBrowserBinding {
  /** Already authenticated and scoped to a device/allocation. Must not retry a dispatched mutation. */
  call(method: string, params: Record<string, unknown>): Promise<unknown>;
  /** The device's advertised methods, in native camelCase. */
  methods: ReadonlySet<string>;
}
const response = z.object({ success: z.boolean().optional(), error: z.unknown().optional() }).passthrough();
const tab = z.object({ id: z.string(), url: z.string().optional(), title: z.string().optional() });
const node = z.object({ role: z.string().max(256).optional(), name: z.string().max(100_000).optional(), selector: z.string().max(4096).optional() });
interface Target { selector: string; role: string; name: string }

/** Native HTTP and device-socket routes share this adapter; authentication belongs to the caller. */
export function createKelpieBrowserBackend(binding: KelpieBrowserBinding): BrowserControlBackend {
  const refs = new Map<string, { url: string; targets: Map<string, Target> }>();
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
  const tree = async (id: string): Promise<Target[]> => {
    const result = await call("getAccessibilityTree", { tabId: id });
    const stack: unknown[] = Array.isArray(result.tree) ? [...result.tree].reverse() : [result.tree];
    const targets: Target[] = [];
    let visited = 0;
    while (stack.length && ++visited <= 5000) {
      const raw = stack.pop();
      const parsed = node.safeParse(raw);
      if (!parsed.success) continue;
      const n = parsed.data;
      if (n.role || n.name) targets.push({ selector: n.selector ?? "", role: n.role ?? "", name: n.name ?? "" });
      const children = (raw as { children?: unknown }).children;
      if (Array.isArray(children)) stack.push(...[...children].reverse());
    }
    return targets;
  };
  const act = async (request: Extract<BrowserControlRequest, { method: "tab.click" | "tab.type" }>) => {
    const id = request.tabId ?? "";
    const saved = refs.get(id);
    const target = saved?.targets.get(request.params.ref);
    if (!target?.selector || saved?.url !== (await current(id)).url) throw new BrowserControlError("STALE_REFERENCE", "Observe this tab again before acting.");
    const fresh = (await tree(id)).filter((item) => item.selector === target.selector);
    if (fresh.length !== 1 || fresh[0]?.role !== target.role || fresh[0].name !== target.name) throw new BrowserControlError("STALE_REFERENCE", "That element changed. Observe this tab again.");
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
  if (has("getCurrentUrl", "getAccessibilityTree")) {
    operations["tab.snapshot"] = async (request) => {
      const id = request.tabId ?? "";
      refs.delete(id);
      const page = await current(id);
      const targets = await tree(id);
      const prefix = `s${String(++generation)}e`;
      const elements = targets.map((target, i) => ({ ref: `${prefix}${String(i + 1)}`, role: target.role, name: target.name }));
      const snapshot = browserSnapshot({ ...page, elements }, request.params);
      const observed = new Map(snapshot.elements?.map((el) => [el.ref, targets[elements.findIndex((item) => item.ref === el.ref)] as Target]));
      refs.set(id, { url: page.url, targets: observed });
      return snapshot;
    };
    if (has("click")) operations["tab.click"] = act;
    if (has("type")) operations["tab.type"] = act;
  }
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
    try { return await backend.execute(request); }
    finally { if (request.tabId && browserControlMutates(request.method)) refs.delete(request.tabId); }
  } };
}
