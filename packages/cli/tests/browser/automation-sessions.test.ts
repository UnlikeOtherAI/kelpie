import { describe, expect, it, vi } from "vitest";
import { BrowserControlError } from "@unlikeotherai/kelpie-shared/browser-control";
import type { ManagedBrowserSession } from "@unlikeotherai/kelpie-shared/browser-control";
import { createManagedSessionRegistry } from "../../src/browser/automation-sessions.js";

function fixture() {
  let id = 0;
  const created: ManagedBrowserSession[] = [];
  const allocate = vi.fn(async () => {
    const sessionId = "owned-" + String(++id);
    const session: ManagedBrowserSession = {
      describe: vi.fn<ManagedBrowserSession["describe"]>(() => ({ version: 1, sessionId, backend: "playwright", isolation: "isolated", ownedTabIds: ["tab-" + sessionId], expiresAt: "2030-01-01T00:00:00.000Z" })),
      backend: { capabilities: { version: 1, methods: [], extensions: [] }, execute: vi.fn() },
      transport: { call: vi.fn<ManagedBrowserSession["transport"]["call"]>(async () => ({ version: 1, ok: true, value: null })) },
      close: vi.fn(async () => undefined),
    };
    created.push(session);
    return session;
  });
  const authorize = vi.fn();
  const registry = createManagedSessionRegistry({ owner: "opaque-principal", authorize, allocate, maxSessions: 1 });
  return { registry, allocate, authorize, created };
}

describe("worker transport registry", () => {
  it("keeps owner internal and refuses foreign session ids", async () => {
    const f = fixture();
    const session = await f.registry.create({ isolation: "isolated" });
    expect(session.sessionId).toBe("owned-1");
    expect(f.allocate).toHaveBeenCalledWith({ isolation: "isolated", ttlMs: 300_000 });
    expect(JSON.stringify(await f.registry.list())).not.toContain("opaque-principal");
    await expect(f.registry.describe("foreign")).rejects.toMatchObject({ code: "SESSION_NOT_FOUND" });
    await expect(f.registry.call("foreign", { version: 1, method: "tabs.list", params: {} })).rejects.toMatchObject({ code: "SESSION_NOT_FOUND" });
    await f.registry.dispose();
  });

  it("does not admit extra sessions or endpoint fields", async () => {
    const f = fixture();
    await f.registry.create({ isolation: "isolated" });
    await expect(f.registry.create({ isolation: "isolated" })).rejects.toMatchObject({ code: "RESOURCE_LIMIT" });
    await expect(f.registry.create({ isolation: "isolated", endpoint: "ws://foreign" } as never)).rejects.toThrow();
    expect(f.allocate).toHaveBeenCalledOnce();
    await f.registry.dispose();
  });

  it("authorizes before forwarding commands and permanently closes on disposal", async () => {
    const f = fixture();
    const session = await f.registry.create({ isolation: "isolated" });
    f.authorize.mockImplementation(() => { throw new Error("revoked"); });
    await expect(f.registry.call(session.sessionId, { version: 1, method: "tabs.list", params: {} })).rejects.toThrow("revoked");
    expect(f.created[0]?.transport.call).not.toHaveBeenCalled();
    await f.registry.dispose();
    await expect(f.registry.list()).rejects.toMatchObject({ code: "SESSION_CLOSED" });
    expect(f.created[0]?.close).toHaveBeenCalledOnce();
  });

  it("retains failed resource cleanup for retry without silently deleting the session", async () => {
    const f = fixture();
    const session = await f.registry.create({ isolation: "isolated" });
    vi.mocked(f.created[0]!.close).mockRejectedValueOnce(new Error("lost"));
    await expect(f.registry.close(session.sessionId)).rejects.toThrow("lost");
    expect(await f.registry.describe(session.sessionId)).toMatchObject({ sessionId: session.sessionId });
    await f.registry.close(session.sessionId);
    await expect(f.registry.describe(session.sessionId)).rejects.toMatchObject({ code: "SESSION_NOT_FOUND" });
  });

  it("prunes expired sessions through normal cleanup before allocating another", async () => {
    const f = fixture();
    await f.registry.create({ isolation: "isolated" });
    vi.mocked(f.created[0]!.describe).mockImplementation(() => { throw new BrowserControlError("SESSION_CLOSED", "expired"); });
    expect((await f.registry.create({ isolation: "shared" })).sessionId).toBe("owned-2");
    expect(f.created[0]?.close).toHaveBeenCalledOnce();
    await f.registry.dispose();
  });
});
