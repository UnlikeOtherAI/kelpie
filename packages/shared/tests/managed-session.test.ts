import type { Browser, BrowserContext, Page } from "playwright-core";
import { describe, expect, it, vi } from "vitest";
import { allocateManagedBrowserSession } from "../src/browser-control/managed-session.js";
import { createLightpandaBrowserBackend } from "../src/browser-control/lightpanda.js";
import type { BrowserControlRequest } from "../src/browser-control/protocol.js";
import type { ManagedBrowserSessionOptions } from "../src/browser-control/managed-session.js";

const request = (method: BrowserControlRequest["method"], params = {}, tabId?: string): BrowserControlRequest =>
  ({ version: 1, method, params, tabId } as BrowserControlRequest);

function fixture() {
  const created: ReturnType<typeof makePage>[] = [];
  function makePage() {
    const listeners = new Map<string, (...args: never[]) => void>();
    let closed = false;
    let url = "about:blank";
    const page = {
      isClosed: () => closed, url: () => url, context: () => context as unknown as BrowserContext,
      once: vi.fn((event: string, callback: (...args: never[]) => void) => { listeners.set(event, callback); }),
      on: vi.fn(), off: vi.fn(),
      evaluate: vi.fn<() => Promise<unknown>>(async () => ({ ok: true, value: { available: false } })),
      goto: vi.fn(async (value: string) => { url = value; }),
      title: vi.fn(async () => "Fixture"),
      close: vi.fn(async () => { closed = true; listeners.get("close")?.(); }),
    };
    return page;
  }
  const context = {
    newCDPSession: vi.fn(async (page: Page) => ({
      on: vi.fn(), detach: vi.fn(async () => undefined),
      send: vi.fn(async (method: string) => {
        if (method === "Page.getFrameTree") return { frameTree: { frame: { id: "frame", url: page.url() } } };
        if (method === "Page.createIsolatedWorld") return { executionContextId: 7 };
        if (method === "Runtime.evaluate") return { result: { value: await page.evaluate(() => undefined) } };
        return {};
      }),
    })),
    newPage: vi.fn(async () => { const page = makePage(); created.push(page); return page as unknown as Page; }),
    close: vi.fn(async () => { await Promise.all(created.map((page) => page.close())); }),
    pages: vi.fn(() => { throw new Error("Must not enumerate shared human pages"); }),
  };
  const browser = { newContext: vi.fn(async () => context as unknown as BrowserContext), close: vi.fn() };
  const authorize = vi.fn();
  const input: ManagedBrowserSessionOptions = {
    browser: browser as unknown as Browser, owner: "opaque-uoa-subject", authorize,
    backend: "playwright", options: { isolation: "isolated", ttlMs: 300_000 },
    network: { boundary: "operator-enforced", allowNavigation: (url) => url.hostname === "allowed.example" },
  };
  return { input, browser, context, created, authorize };
}

describe("restricted Lightpanda profile", () => {
  it("starts unverified and refuses pixels even if public metadata is edited", async () => {
    const binding = { listTabs: vi.fn(), getPage: vi.fn() };
    const backend = createLightpandaBrowserBackend(binding);
    expect(backend.capabilities.methods).toEqual(["documentation", "capabilities"]);
    backend.capabilities.methods.push("tab.screenshot");
    await expect(backend.execute(request("tab.screenshot", {}, "owned"))).rejects.toMatchObject({ code: "UNSUPPORTED", mayHaveCompleted: false });
    expect(binding.getPage).not.toHaveBeenCalled();
  });

  it.each(["tab.snapshot", "tab.extract", "tab.status", "tab.ready"] as const)(
    "requires explicit operator verification for %s without granting input or pixels", async (method) => {
      const value = method === "tab.snapshot" ? { snapshot: { elements: [], text: "" } } : { marker: method };
      const page = { evaluate: vi.fn(async () => value) };
      const binding = { listTabs: vi.fn(), getPage: vi.fn(async () => page as unknown as Page) };
      const unverified = createLightpandaBrowserBackend(binding);
      await expect(unverified.execute(request(method, {}, "owned"))).rejects.toMatchObject({ code: "UNSUPPORTED" });
      expect(binding.getPage).not.toHaveBeenCalled();
      const backend = createLightpandaBrowserBackend(binding, [method]);
      expect(backend.capabilities.methods).toContain(method);
      backend.capabilities.methods.push("tab.screenshot");
      await expect(backend.execute(request("tab.screenshot", {}, "owned"))).rejects.toMatchObject({ code: "UNSUPPORTED" });
      const params = method === "tab.extract" ? { fields: [{ name: "title", selector: "h1", source: "text" }] } : {};
      await expect(backend.execute(request(method, params, "owned"))).resolves.toEqual(
        method === "tab.snapshot" ? { elements: [], text: "" } : { marker: method });
      expect(page.evaluate).toHaveBeenCalledOnce();
    },
  );

  it("admits only operator-verified candidates with actual binding operations", async () => {
    const binding = { listTabs: vi.fn(async () => [{ id: "owned" }]), getPage: vi.fn() };
    const backend = createLightpandaBrowserBackend(binding, ["tabs.list"]);
    expect(await backend.execute(request("tabs.list"))).toEqual([{ id: "owned" }]);
    expect(() => createLightpandaBrowserBackend(binding, ["tabs.new"])).toThrow(/does not implement/);
    expect(() => createLightpandaBrowserBackend(binding, ["locator.click" as never])).toThrow(/cannot admit/);
  });
});

describe("operator-managed automation sessions", () => {
  it("refuses unverified Lightpanda shared isolation before any allocation or borrowed-context access", async () => {
    const f = fixture();
    f.input.backend = "lightpanda";
    f.input.options.isolation = "shared";
    f.input.sharedContext = f.context as unknown as BrowserContext;
    await expect(allocateManagedBrowserSession(f.input)).rejects.toMatchObject({
      code: "ISOLATION_UNAVAILABLE", mayHaveCompleted: false,
    });
    expect(f.browser.newContext).not.toHaveBeenCalled();
    expect(f.context.newPage).not.toHaveBeenCalled();
    expect(f.context.pages).not.toHaveBeenCalled();
    expect(f.context.close).not.toHaveBeenCalled();
    expect(f.browser.close).not.toHaveBeenCalled();
    expect(f.created).toHaveLength(0);
  });

  it("owns fresh isolated storage and refuses foreign tabs without enumeration", async () => {
    const f = fixture();
    const session = await allocateManagedBrowserSession(f.input);
    try {
      expect(f.browser.newContext).toHaveBeenCalledWith({ serviceWorkers: "block", acceptDownloads: false });
      const descriptor = session.describe();
      expect(JSON.stringify(descriptor)).not.toContain("opaque-uoa-subject");
      expect(descriptor.ownedTabIds).toHaveLength(1);
      await expect(session.backend.execute(request("tab.url", {}, "human-tab"))).rejects.toMatchObject({ code: "TAB_NOT_FOUND" });
      expect(f.context.pages).not.toHaveBeenCalled();
      expect(await session.backend.execute(request("tabs.list"))).toEqual([{ id: descriptor.ownedTabIds[0], url: "about:blank" }]);
    } finally { await session.close(); }
    expect(f.context.close).toHaveBeenCalledOnce();
    expect(f.browser.close).not.toHaveBeenCalled();
  });

  it("requires explicit shared context and closes only its fresh owned pages", async () => {
    const f = fixture();
    f.input.options.isolation = "shared";
    await expect(allocateManagedBrowserSession(f.input)).rejects.toMatchObject({ code: "ISOLATION_UNAVAILABLE" });
    f.input.sharedContext = f.context as unknown as BrowserContext;
    const session = await allocateManagedBrowserSession(f.input);
    await session.close();
    expect(f.context.close).not.toHaveBeenCalled();
    expect(f.context.pages).not.toHaveBeenCalled();
    expect(f.created[0]?.close).toHaveBeenCalledOnce();
    expect(f.browser.newContext).not.toHaveBeenCalled();
  });

  it("enforces requested URL and tab budgets before browser work", async () => {
    const f = fixture();
    f.input.maxTabs = 1;
    const session = await allocateManagedBrowserSession(f.input);
    try {
      const id = session.describe().ownedTabIds[0];
      for (const url of ["file:///private", "https://user:secret@allowed.example/", "https://foreign.example/"]) {
        await expect(session.backend.execute(request("tab.goto", { url }, id))).rejects.toMatchObject({ code: "ACCESS_DENIED" });
      }
      expect(f.created[0]?.goto).not.toHaveBeenCalled();
      await expect(session.backend.execute(request("tabs.new"))).rejects.toMatchObject({ code: "RESOURCE_LIMIT" });
      expect(f.context.newPage).toHaveBeenCalledOnce();
    } finally { await session.close(); }
  });

  it("rechecks revocation after async admission and refuses future commands", async () => {
    const f = fixture();
    const session = await allocateManagedBrowserSession(f.input);
    try {
      const id = session.describe().ownedTabIds[0];
      f.authorize.mockImplementation(() => { throw new Error("revoked"); });
      await expect(session.backend.execute(request("tab.goto", { url: "https://allowed.example/" }, id))).rejects.toThrow("revoked");
      expect(f.created[0]?.goto).not.toHaveBeenCalled();
      const response = await session.transport.call(request("capabilities"));
      expect(response).toMatchObject({ ok: false, error: { code: "COMMAND_FAILED", mayHaveCompleted: false } });
      expect(JSON.stringify(response)).not.toContain("revoked");
    } finally { await session.close(); }
  });

  it("expires automatically and closes owned resources without closing browser", async () => {
    vi.useFakeTimers();
    const f = fixture();
    f.input.options.ttlMs = 1000;
    try {
      const session = await allocateManagedBrowserSession(f.input);
      await vi.advanceTimersByTimeAsync(1001);
      expect(() => session.describe()).toThrow(/closed or expired/);
      await expect(session.backend.execute(request("tabs.list"))).rejects.toMatchObject({ code: "SESSION_CLOSED" });
      expect(f.context.close).toHaveBeenCalledOnce();
      expect(f.browser.close).not.toHaveBeenCalled();
      expect(await session.transport.call(request("capabilities"))).toMatchObject({ ok: false, error: { code: "SESSION_CLOSED" } });
    } finally { vi.useRealTimers(); }
  });

  it("retains a dispatched mutation's uncertainty when access ends before completion", async () => {
    const f = fixture();
    const session = await allocateManagedBrowserSession(f.input);
    const id = session.describe().ownedTabIds[0];
    f.created[0]!.goto.mockImplementation(async () => { await session.close(); });
    await expect(session.backend.execute(request("tab.goto", { url: "https://allowed.example/" }, id)))
      .rejects.toMatchObject({ code: "SESSION_CLOSED", mayHaveCompleted: true });
  });

  it("rejects an invalid capability profile before allocating a context", async () => {
    const f = fixture();
    f.input.backend = "lightpanda";
    f.input.verifiedLightpandaMethods = ["tab.screenshot" as never];
    await expect(allocateManagedBrowserSession(f.input)).rejects.toMatchObject({ code: "UNSUPPORTED" });
    expect(f.browser.newContext).not.toHaveBeenCalled();
    expect(f.context.newPage).not.toHaveBeenCalled();
  });

  it("can retry failed cleanup without restoring browser access", async () => {
    const f = fixture();
    const session = await allocateManagedBrowserSession(f.input);
    f.context.close.mockRejectedValueOnce(new Error("transport lost"));
    await expect(session.close()).rejects.toMatchObject({ code: "CLEANUP_PENDING" });
    await expect(session.backend.execute(request("tabs.list"))).rejects.toMatchObject({ code: "SESSION_CLOSED" });
    await session.close();
    expect(f.context.close).toHaveBeenCalledTimes(2);
  });
});

describe("failed allocation cleanup remains owned", () => {
  it("tracks a page before post-creation admission and retries failed initial cleanup", async () => {
    vi.useFakeTimers();
    const f = fixture();
    const original = f.context.newPage.getMockImplementation();
    if (!original) throw new Error("fixture creation missing");
    f.context.newPage.mockImplementationOnce(async () => {
      const page = await original();
      f.created[0]!.close.mockRejectedValueOnce(new Error("page cleanup unavailable"));
      f.authorize.mockImplementation(() => { throw new Error("revoked during allocation"); });
      return page;
    });
    f.context.close.mockRejectedValueOnce(new Error("context cleanup unavailable"));
    try {
      await expect(allocateManagedBrowserSession(f.input)).rejects.toMatchObject({ code: "CLEANUP_PENDING" });
      expect(f.context.close).toHaveBeenCalledOnce();
      expect(f.created[0]?.isClosed()).toBe(false);
      await vi.advanceTimersByTimeAsync(1001);
      expect(f.context.close).toHaveBeenCalledTimes(2);
      expect(f.created[0]?.isClosed()).toBe(true);
    } finally { vi.useRealTimers(); }
  });

  it("retains an unreturned failed tab against the session budget until automatic cleanup", async () => {
    vi.useFakeTimers();
    const f = fixture();
    const session = await allocateManagedBrowserSession(f.input);
    const original = f.context.newPage.getMockImplementation();
    if (!original) throw new Error("fixture creation missing");
    f.context.newPage.mockImplementationOnce(async () => {
      const page = await original();
      f.created[1]!.close.mockRejectedValueOnce(new Error("page cleanup unavailable"));
      f.authorize.mockImplementation(() => { throw new Error("revoked during allocation"); });
      return page;
    });
    try {
      await expect(session.backend.execute(request("tabs.new"))).rejects.toMatchObject({ code: "CLEANUP_PENDING" });
      f.authorize.mockReset();
      expect(await session.backend.execute(request("tabs.list"))).toHaveLength(2);
      await vi.advanceTimersByTimeAsync(1001);
      expect(await session.backend.execute(request("tabs.list"))).toHaveLength(1);
      expect(f.created[1]?.isClosed()).toBe(true);
    } finally { await session.close(); vi.useRealTimers(); }
  });
});

describe("managed operator WebMCP capability gate", () => {
  it("adds canonical methods only with a configured origin and real API probe", async () => {
    const f = fixture();
    f.input.webMcp = { origins: ["https://allowed.example"], inputEncoding: "json-string" };
    const session = await allocateManagedBrowserSession(f.input);
    try {
      expect(session.backend.capabilities.methods).not.toContain("tab.webmcp.call");
      f.created[0]!.evaluate.mockResolvedValue({ ok: true, value: { available: true, api: "document.modelContext" } });
      await session.backend.execute(request("tab.goto", { url: "https://allowed.example/" }, session.describe().ownedTabIds[0]));
      expect(session.backend.capabilities.methods).toContain("tab.webmcp.discover");
      expect(session.backend.capabilities.methods).toContain("tab.webmcp.call");
      expect(f.created[0]?.evaluate).toHaveBeenCalledOnce();
    } finally { await session.close(); }
  });

  it("does not advertise an absent browser API or infer a grant from request origin", async () => {
    const f = fixture();
    const session = await allocateManagedBrowserSession(f.input);
    try {
      const id = session.describe().ownedTabIds[0];
      await session.backend.execute(request("tab.goto", { url: "https://allowed.example/" }, id));
      expect(f.created[0]?.evaluate).not.toHaveBeenCalled();
      const result = await session.transport.call(request("tab.webmcp.discover", { origin: "https://allowed.example" }, id));
      expect(result).toMatchObject({ ok: false, error: { code: "UNSUPPORTED", mayHaveCompleted: false } });
    } finally { await session.close(); }
  });

  it("withholds site tools when an authorized origin has no real API", async () => {
    const f = fixture();
    f.input.webMcp = { origins: ["https://allowed.example"], inputEncoding: "json-string" };
    const session = await allocateManagedBrowserSession(f.input);
    try {
      const id = session.describe().ownedTabIds[0];
      await session.backend.execute(request("tab.goto", { url: "https://allowed.example/" }, id));
      expect(session.backend.capabilities.methods).not.toContain("tab.webmcp.call");
      expect(await session.transport.call(request("tab.webmcp.discover", { origin: "https://allowed.example" }, id)))
        .toMatchObject({ ok: false, error: { code: "UNSUPPORTED" } });
    } finally { await session.close(); }
  });

  it("rejects unaudited trusted configuration before allocating browser resources", async () => {
    const f = fixture();
    f.input.webMcp = { origins: ["https://allowed.example"], inputEncoding: "guess" as never };
    await expect(allocateManagedBrowserSession(f.input)).rejects.toMatchObject({ code: "INVALID_ARGUMENTS" });
    expect(f.browser.newContext).not.toHaveBeenCalled();
  });
});
