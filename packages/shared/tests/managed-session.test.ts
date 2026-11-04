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
      isClosed: () => closed, url: () => url,
      once: vi.fn((event: string, callback: (...args: never[]) => void) => { listeners.set(event, callback); }),
      on: vi.fn(),
      goto: vi.fn(async (value: string) => { url = value; }),
      title: vi.fn(async () => "Fixture"),
      close: vi.fn(async () => { closed = true; listeners.get("close")?.(); }),
    };
    return page;
  }
  const context = {
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

  it("admits only operator-verified candidates with actual binding operations", async () => {
    const binding = { listTabs: vi.fn(async () => [{ id: "owned" }]), getPage: vi.fn() };
    const backend = createLightpandaBrowserBackend(binding, ["tabs.list"]);
    expect(await backend.execute(request("tabs.list"))).toEqual([{ id: "owned" }]);
    expect(() => createLightpandaBrowserBackend(binding, ["tabs.new"])).toThrow(/does not implement/);
    expect(() => createLightpandaBrowserBackend(binding, ["locator.click" as never])).toThrow(/cannot admit/);
  });
});

describe("operator-managed automation sessions", () => {
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
    await expect(session.close()).rejects.toMatchObject({ code: "CLEANUP_FAILED" });
    await expect(session.backend.execute(request("tabs.list"))).rejects.toMatchObject({ code: "SESSION_CLOSED" });
    await session.close();
    expect(f.context.close).toHaveBeenCalledTimes(2);
  });
});
