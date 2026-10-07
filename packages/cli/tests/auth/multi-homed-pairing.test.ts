import { it, expect, vi } from "vitest";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { TokenStore, setTokenStoreForTesting } from "../../src/auth/token-store.js";
import { sendCommand } from "../../src/client/http-client.js";
import { orderAddresses } from "../../src/discovery/scanner.js";
import type { DiscoveredDevice } from "../../src/types.js";

// A Mac on Ethernet + Wi-Fi in one subnet answers mDNS on both interfaces.
function multiHomed(ip: string): DiscoveredDevice {
  return {
    id: "native", name: "Mac", ip, addresses: ["192.168.1.77", "192.168.1.229"], port: 8420,
    platform: "macos", model: "Mac", width: 0, height: 0, version: "test", lastSeen: Date.now(),
  };
}

it("reuses an Always approval when mDNS resolves the device on another interface", async () => {
  const dir = await mkdtemp(join(tmpdir(), "kelpie-multihome-test-"));
  const originalFetch = globalThis.fetch;
  try {
    const store = new TokenStore(dir);
    await store.set("native", "192.168.1.229", 8420, "always");
    setTokenStoreForTesting(store);
    const calls: string[] = [];
    globalThis.fetch = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
      const authorization = (init?.headers as Record<string, string>).Authorization ?? "";
      calls.push(`${String(url)} ${authorization}`);
      const ok = authorization === "Bearer always";
      return new Response(JSON.stringify({ success: ok }), { status: ok ? 200 : 401 });
    }) as typeof fetch;

    // Discovery picked the other interface; no pair request may be sent.
    expect((await sendCommand(multiHomed("192.168.1.77"), "getTabs")).ok).toBe(true);
    expect(calls).toEqual(["http://192.168.1.229:8420/v1/get-tabs Bearer always"]);
  } finally {
    globalThis.fetch = originalFetch;
    setTokenStoreForTesting(null);
    await rm(dir, { recursive: true, force: true });
  }
});

it("never sends a pinned token to an address that was not advertised", async () => {
  const dir = await mkdtemp(join(tmpdir(), "kelpie-multihome-test-"));
  const originalFetch = globalThis.fetch;
  try {
    const store = new TokenStore(dir);
    await store.set("native", "192.168.1.50", 8420, "always");
    setTokenStoreForTesting(store);
    const authorizations: string[] = [];
    globalThis.fetch = vi.fn(async (_url: string | URL | Request, init?: RequestInit) => {
      authorizations.push((init?.headers as Record<string, string>).Authorization ?? "");
      return new Response(JSON.stringify({ success: true }), { status: 200 });
    }) as typeof fetch;

    await sendCommand(multiHomed("192.168.1.77"), "getTabs");
    expect(authorizations).toEqual([""]);
  } finally {
    globalThis.fetch = originalFetch;
    setTokenStoreForTesting(null);
    await rm(dir, { recursive: true, force: true });
  }
});

it("orders advertised addresses deterministically", () => {
  const expected = ["192.168.1.229", "192.168.1.77", "2001:db8::1", "fe80::1"];
  expect(orderAddresses(["fe80::1", "192.168.1.77", "2001:db8::1", "192.168.1.229", "192.168.1.77"]))
    .toEqual(expected);
  expect(orderAddresses(["192.168.1.77", "fe80::1", "192.168.1.229", "2001:db8::1"])).toEqual(expected);
});
