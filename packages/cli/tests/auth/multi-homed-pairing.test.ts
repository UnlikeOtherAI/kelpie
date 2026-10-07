import { it, expect, vi, beforeEach, afterEach } from "vitest";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { TokenStore, setTokenStoreForTesting } from "../../src/auth/token-store.js";
import { sendCommand } from "../../src/client/http-client.js";
import type { DiscoveredDevice } from "../../src/types.js";

// A Mac on Ethernet (.229) and Wi-Fi (.77) in one subnet: mDNS answers with
// either address, while each "Always allow" token is pinned to one socket.
function discoveredAt(ip: string): DiscoveredDevice {
  return {
    id: "native", name: "Mac", ip, port: 8420,
    platform: "macos", model: "Mac", width: 0, height: 0, version: "test", lastSeen: Date.now(),
  };
}

let dir: string;
let store: TokenStore;
let calls: string[];
const originalFetch = globalThis.fetch;

/** Device accepts only `valid`; pairing requests are denied so a prompt is observable. */
function mockDevice(valid: string): void {
  globalThis.fetch = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
    const authorization = (init?.headers as Record<string, string> | undefined)?.Authorization ?? "";
    calls.push(`${String(url)} ${authorization}`.trim());
    if (String(url).endsWith("/v1/pair")) {
      return new Response(JSON.stringify({ error: { code: "DENIED", message: "denied" } }), { status: 403 });
    }
    const ok = authorization === `Bearer ${valid}`;
    return new Response(JSON.stringify({ success: ok }), { status: ok ? 200 : 401 });
  }) as typeof fetch;
}

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "kelpie-multihome-test-"));
  store = new TokenStore(dir);
  setTokenStoreForTesting(store);
  calls = [];
  vi.spyOn(process.stderr, "write").mockImplementation(() => true);
});

afterEach(async () => {
  globalThis.fetch = originalFetch;
  setTokenStoreForTesting(null);
  vi.restoreAllMocks();
  await rm(dir, { recursive: true, force: true });
});

it("reuses an Always approval when mDNS resolves the device on another interface", async () => {
  await store.set("native", "192.168.1.229", 8420, "always");
  mockDevice("always");

  const device = discoveredAt("192.168.1.77");
  expect((await sendCommand(device, "getTabs")).ok).toBe(true);
  expect(calls).toEqual([
    "http://192.168.1.77:8420/v1/get-tabs",
    "http://192.168.1.229:8420/v1/get-tabs Bearer always",
  ]);
  // The device is re-routed, so later calls go straight to the approved socket.
  calls.length = 0;
  expect((await sendCommand(device, "getTabs")).ok).toBe(true);
  expect(calls).toEqual(["http://192.168.1.229:8420/v1/get-tabs Bearer always"]);
});

it("skips an approval the device replaced and keeps the current one", async () => {
  // Re-approving at .77 replaced the device's record, revoking the .229 token.
  await store.set("native", "192.168.1.229", 8420, "revoked");
  await store.set("native", "192.168.1.77", 8420, "current");
  mockDevice("current");

  expect((await sendCommand(discoveredAt("192.168.1.229"), "getTabs")).ok).toBe(true);
  expect(calls).toEqual([
    "http://192.168.1.229:8420/v1/get-tabs Bearer revoked",
    "http://192.168.1.77:8420/v1/get-tabs Bearer current",
  ]);
  expect(await store.get("native", "192.168.1.229", 8420)).toBeUndefined();
  expect(await store.get("native", "192.168.1.77", 8420)).toBe("current");
});

it("never sends another device's token or a token to a socket that did not approve it", async () => {
  await store.set("other-device", "192.168.1.229", 8420, "foreign");
  mockDevice("foreign");

  expect((await sendCommand(discoveredAt("192.168.1.77"), "getTabs")).ok).toBe(false);
  expect(calls).toEqual([
    "http://192.168.1.77:8420/v1/get-tabs",
    "http://192.168.1.77:8420/v1/pair",
  ]);
});
