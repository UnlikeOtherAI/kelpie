import { describe, expect, it } from "vitest";
import { BrowserControlRequestSchema, browserControlMutates } from "../src/browser-control/protocol.js";
import { createBrowserControlProxy } from "../src/browser-control/proxy.js";
import { createPlaywrightBrowserBackend } from "../src/browser-control/playwright.js";

describe("observation contracts", () => {
  it("bounds nested extraction and rejects arbitrary value/attribute/code sources", () => {
    const field = { name: "title", selector: "h1" };
    const request = (fields: unknown[]) => ({ version: 1, method: "tab.extract", tabId: "a", params: { fields } });
    expect(BrowserControlRequestSchema.safeParse(request([field])).success).toBe(true);
    expect(BrowserControlRequestSchema.safeParse(request([{ ...field, source: "value" }])).success).toBe(false);
    expect(BrowserControlRequestSchema.safeParse(request([{ ...field, attribute: "data-secret" }])).success).toBe(false);
    const nested = { ...field, fields: [{ ...field, fields: [field] }] };
    expect(BrowserControlRequestSchema.safeParse(request([nested])).success).toBe(true);
    expect(BrowserControlRequestSchema.safeParse(request([{ ...field, fields: [nested] }])).success).toBe(false);
    expect(BrowserControlRequestSchema.safeParse(request(Array.from({ length: 33 }, () => field))).success).toBe(false);
  });
  it("makes readiness immediate and all observations read-only", () => {
    for (const method of ["tab.snapshot", "tab.extract", "tab.status", "tab.ready"] as const) expect(browserControlMutates(method)).toBe(false);
    const input = { version: 1, method: "tab.ready", tabId: "a", params: {} };
    const ready = BrowserControlRequestSchema.parse(input);
    expect(ready.params).toEqual({ state: "interactive" });
    expect(BrowserControlRequestSchema.safeParse({ ...input, params: { timeoutMs: 500 } }).success).toBe(false);
  });
  it("authorizes every observation before resolving an owned page and scrubs results", async () => {
    let reached = false;
    const backend = createPlaywrightBrowserBackend({
      listTabs: async () => [],
      getPage: async () => { reached = true; throw new Error("PRIVATE"); },
    });
    const transport = createBrowserControlProxy(backend, { authorize: () => { throw new Error("PRIVATE"); } });
    const result = await transport.call({ version: 1, method: "tab.status", tabId: "foreign", params: {} });
    expect(reached).toBe(false);
    expect(JSON.stringify(result)).not.toContain("PRIVATE");
    expect(result.ok).toBe(false);
  });
});
