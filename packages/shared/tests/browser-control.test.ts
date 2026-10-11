import { z } from "zod";
import { describe, expect, it, vi } from "vitest";
import {
  BrowserControlError, BrowserControlEnvelopeSchema, BrowserControlRequestSchema, BROWSER_CONTROL_DESCRIPTION, browserControlInputSchema,
  browserSnapshot, createBrowserBackend, createBrowserClient, createBrowserControlProxy,
  createKelpieBrowserBackend,
} from "../src/browser-control/index.js";
import type { BrowserControlRequest } from "../src/browser-control/index.js";

const request = (method: BrowserControlRequest["method"], params = {}, tabId = "a"): BrowserControlRequest => ({ version: 1, method, params, tabId } as BrowserControlRequest);

describe("browser control boundary", () => {
  it("rejects unknown fields, versions, methods and unbounded arguments", () => {
    for (const input of [
      { ...request("tabs.list"), version: 2 }, { ...request("tabs.list"), credential: "secret" },
      request("tab.click", { ref: "e1", selector: "#guess" }), request("tab.type", { ref: "e1", text: "x".repeat(65_537) }),
      request("page.scroll", { deltaY: Infinity }), { ...request("tabs.list"), method: "evaluate" },
    ]) expect(BrowserControlRequestSchema.safeParse(input).success).toBe(false);
  });

  it("authorizes reads and metadata, refuses unsupported calls before execution", async () => {
    const authorize = vi.fn();
    const execute = vi.fn();
    const proxy = createBrowserControlProxy({ capabilities: { version: 1, methods: ["tab.url"], extensions: [] }, execute }, { authorize });
    expect(await proxy.call(request("capabilities"))).toMatchObject({ ok: true });
    expect(await proxy.call(request("tab.goto", { url: "https://example.org" }))).toMatchObject({ ok: false, error: { code: "UNSUPPORTED", mayHaveCompleted: false } });
    expect(authorize).toHaveBeenCalledTimes(2);
    expect(execute).not.toHaveBeenCalled();
  });

  it("serializes actions, never retries and recovers its queue without leaking backend errors", async () => {
    const calls: string[] = [];
    const proxy = createBrowserControlProxy(createBrowserBackend({
      "tab.goto": async () => { calls.push("goto"); throw new Error("SECRET_TOKEN cdp://credentials"); },
      "tab.url": async () => { calls.push("url"); return "https://example.org"; },
    }));
    const [action, read] = await Promise.all([proxy.call(request("tab.goto", { url: "https://example.org" })), proxy.call(request("tab.url"))]);
    expect(action).toMatchObject({ ok: false, error: { mayHaveCompleted: true } });
    expect(JSON.stringify(action)).not.toContain("SECRET_TOKEN");
    expect(read).toMatchObject({ ok: true });
    expect(calls).toEqual(["goto", "url"]);
  });

  it("preserves typed rejections and product fatal unknown-outcome fences", async () => {
    const fatal = new Error("durable fatal fence");
    const proxy = createBrowserControlProxy(createBrowserBackend({ "tab.url": async () => { throw fatal; } }), { isFatalError: (error) => error === fatal });
    await expect(proxy.call(request("tab.url"))).rejects.toBe(fatal);
    const denied = createBrowserControlProxy(createBrowserBackend({}), { authorize: () => { throw new BrowserControlError("ACCESS_DENIED", "Not admitted."); } });
    expect(await denied.call(request("documentation"))).toMatchObject({ ok: false, error: { code: "ACCESS_DENIED", mayHaveCompleted: false } });
  });

  it("derives compact scoped schemas from the same request variants", () => {
    const full = browserControlInputSchema();
    const compact = browserControlInputSchema({ methods: ["tab.goto", "tab.click", "tab.type"], compact: true });
    expect(JSON.stringify(compact).length).toBeLessThan(1500);
    const scoped = browserControlInputSchema({ methods: ["tabs.list", "tabs.new", "tabs.select", "tabs.close", "tab.snapshot", "tab.goto", "tab.click", "tab.type", "page.press", "page.scroll"] });
    expect(JSON.stringify(scoped)).not.toContain("locator.fill");
    expect(JSON.stringify(scoped).length).toBeLessThan(24_000);
    expect(JSON.stringify(full).length).toBeLessThan(24_000);
    console.info("Browser catalogue bytes", { expanded: JSON.stringify(z.toJSONSchema(BrowserControlEnvelopeSchema)).length, factored: JSON.stringify(full).length, restricted: JSON.stringify(scoped).length, compact: JSON.stringify(compact).length, description: BROWSER_CONTROL_DESCRIPTION.length });
  });

  it("bounds metadata and exposes only normalized fields in snapshots", () => {
    const value = browserSnapshot({ url: "u".repeat(9000), title: "t".repeat(9000), elements: [{ ref: "e1", role: "textbox", name: " Email ", value: "SECRET" } as never] }, { maxChars: 256 });
    expect(value.text.length).toBeLessThanOrEqual(256);
    expect(value.url.length).toBeLessThanOrEqual(128);
    expect(value.title.length).toBeLessThanOrEqual(64);
    expect(value.truncated).toBe(true);
    expect(JSON.stringify(value)).not.toContain("SECRET");
  });

  it("provides the async Codex-shaped client and binary screenshots", async () => {
    const transport = { call: vi.fn(async (input: BrowserControlRequest) => ({ version: 1 as const, ok: true as const, value: input.method === "tab.screenshot" ? { type: "image", mimeType: "image/png", data: "AQID" } : null })) };
    const browser = createBrowserClient(transport);
    const tab = await browser.tabs.get("a");
    expect(await tab.screenshot()).toEqual(Uint8Array.from([1, 2, 3]));
    await tab.click("e1");
    await tab.typeText("e2", "append");
    await tab.pressKey(null, "Enter");
    expect(transport.call).toHaveBeenLastCalledWith(request("page.press", { key: "Enter" }));
    await expect(tab.pressKey("e2", "Enter")).rejects.toMatchObject({ code: "UNSUPPORTED_OPERATION" });
    await expect(tab.typeText(null, "text")).rejects.toMatchObject({ code: "UNSUPPORTED_OPERATION" });
    await tab.playwright.getByRole("button", { name: "Save", exact: true }).click();
    expect(transport.call).toHaveBeenLastCalledWith(request("locator.click", { locator: [{ kind: "role", role: "button", name: "Save", exact: true }] }));
  });
});

describe("native Kelpie adapter", () => {
  it("advertises observed actions only when the fixed-reader evaluation route is admitted", () => {
    const backend = createKelpieBrowserBackend({ methods: new Set(["getCurrentUrl", "getAccessibilityTree", "click", "pressKey"]), call: vi.fn() });
    expect(backend.capabilities.methods).not.toContain("tab.snapshot");
    expect(backend.capabilities.methods).not.toContain("tab.click");
    expect(backend.capabilities.methods).not.toContain("locator.click");
  });

  it("selects mobile tabs explicitly and invalidates refs after failed mutations", async () => {
    const call = vi.fn(async (method: string) => {
      if (method === "evaluate") return { success: true, result: { url: "https://example.org", title: "Fixture", text: "[e1] textbox Email", truncated: false, elements: [{ ref: "e1", role: "textbox", name: "Email" }] } };
      if (method === "navigate") throw new Error("response lost");
      return { success: true };
    });
    const proxy = createBrowserControlProxy(createKelpieBrowserBackend({ methods: new Set(["evaluate", "click", "navigate", "switchTab"]), targeting: "selected", call }));
    expect(await proxy.call(request("tab.snapshot"))).toMatchObject({ ok: true });
    expect(call.mock.calls.map(([method]) => method)).toEqual(["switchTab", "evaluate"]);
    expect(await proxy.call(request("tab.goto", { url: "https://example.org/next" }))).toMatchObject({ ok: false, error: { mayHaveCompleted: true } });
    expect(await proxy.call(request("tab.click", { ref: "e1" }))).toMatchObject({ ok: false, error: { code: "STALE_REFERENCE", mayHaveCompleted: false } });
    expect(call.mock.calls.filter(([method]) => method === "navigate")).toHaveLength(1);
    expect(call.mock.calls.filter(([method]) => method === "click")).toHaveLength(0);
  });
});
