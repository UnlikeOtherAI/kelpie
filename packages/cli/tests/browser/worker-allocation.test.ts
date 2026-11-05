import type { Browser, BrowserContext, Page } from "playwright-core";
import { describe, expect, it, vi } from "vitest";
import { createWorkerSessionAllocator } from "../../src/worker/allocation.js";
import { workerConfigSchema } from "../../src/worker/config.js";

function fixture(backend: "playwright" | "lightpanda") {
  let closed = false;
  const page = {
    once: vi.fn(), on: vi.fn(), url: () => "about:blank", isClosed: () => closed,
    close: vi.fn(async () => { closed = true; }),
  };
  const context = {
    newPage: vi.fn(async () => page as unknown as Page), close: vi.fn(async () => undefined),
    pages: vi.fn(() => { throw new Error("Borrowed pages must not be enumerated"); }),
  };
  const browser = {
    newContext: vi.fn(async () => context as unknown as BrowserContext), close: vi.fn(),
    contexts: vi.fn(() => { throw new Error("Borrowed contexts must not be enumerated"); }),
  };
  const config = workerConfigSchema.parse({
    version: 1, backend, endpointEnv: "KELPIE_TEST_ENDPOINT", allowedOrigins: ["https://fixture.example"],
    networkBoundary: "operator-enforced", maxSessions: 1, maxTabs: 1,
  });
  const allocation = createWorkerSessionAllocator(browser as unknown as Browser, config, "opaque-operator", () => undefined);
  return { allocation, browser, context, page };
}
describe("operator worker allocation isolation", () => {
  it("refuses Lightpanda shared sessions before creating or using a context", async () => {
    const f = fixture("lightpanda");
    await expect(f.allocation.allocate({ isolation: "shared" })).rejects.toMatchObject({
      code: "ISOLATION_UNAVAILABLE", mayHaveCompleted: false,
    });
    await f.allocation.closeSharedContext();
    expect(f.browser.newContext).not.toHaveBeenCalled();
    expect(f.browser.contexts).not.toHaveBeenCalled();
    expect(f.context.newPage).not.toHaveBeenCalled();
    expect(f.context.pages).not.toHaveBeenCalled();
    expect(f.context.close).not.toHaveBeenCalled();
    expect(f.page.close).not.toHaveBeenCalled();
    expect(f.browser.close).not.toHaveBeenCalled();
  });
  it("keeps Playwright shared storage explicit and closes its owned automation context", async () => {
    const f = fixture("playwright");
    const session = await f.allocation.allocate({ isolation: "shared" });
    expect(f.browser.newContext).toHaveBeenCalledOnce();
    expect(f.context.newPage).toHaveBeenCalledOnce();
    await session.close();
    expect(f.page.close).toHaveBeenCalledOnce();
    expect(f.context.close).not.toHaveBeenCalled();
    await f.allocation.closeSharedContext();
    expect(f.context.close).toHaveBeenCalledOnce();
    expect(f.browser.contexts).not.toHaveBeenCalled();
    expect(f.context.pages).not.toHaveBeenCalled();
    expect(f.browser.close).not.toHaveBeenCalled();
  });
  it("retains Lightpanda isolated allocation and requested resource bounds", async () => {
    const f = fixture("lightpanda");
    const session = await f.allocation.allocate({ isolation: "isolated", ttlMs: 1000 });
    expect(session.describe().isolation).toBe("isolated");
    await session.close();
    expect(f.context.close).toHaveBeenCalledOnce();
    expect(f.browser.close).not.toHaveBeenCalled();
    await expect(f.allocation.allocate({ isolation: "isolated", ttlMs: 3600000 })).rejects.toMatchObject({ code: "RESOURCE_LIMIT" });
    expect(f.browser.newContext).toHaveBeenCalledOnce();
  });
});
