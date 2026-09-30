import { it, expect, vi } from "vitest";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { TokenStore, setTokenStoreForTesting } from "../../src/auth/token-store.js";
import { sendCommand } from "../../src/client/http-client.js";
import type { DiscoveredDevice } from "../../src/types.js";

const device: DiscoveredDevice = {
  id: "native", name: "Mac", ip: "192.168.1.229", port: 8420,
  platform: "macos", model: "Mac", width: 0, height: 0,
  version: "test", lastSeen: Date.now(),
};

it("uses a separately approved token after rejection without another pairing prompt", async () => {
  const dir = await mkdtemp(join(tmpdir(), "kelpie-refresh-test-"));
  const originalFetch = globalThis.fetch;
  try {
    const mcp = new TokenStore(dir), cli = new TokenStore(dir);
    await mcp.set(device.id, device.ip, device.port, "old");
    setTokenStoreForTesting(mcp);
    const authorizations: string[] = [];
    globalThis.fetch = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
      expect(String(url)).toBe("http://192.168.1.229:8420/v1/get-tabs");
      const authorization = (init?.headers as Record<string, string>).Authorization ?? "";
      authorizations.push(authorization);
      if (authorization === "Bearer old") {
        // Another CLI's Always approval completes while MCP's request is in flight.
        await cli.set(`direct:${device.ip}:${device.port}`, device.ip, device.port, "new");
        return new Response(JSON.stringify({ success: false }), { status: 401 });
      }
      return new Response(JSON.stringify({ success: true }), { status: 200 });
    }) as typeof fetch;
    expect((await sendCommand(device, "getTabs")).ok).toBe(true);
    expect(authorizations).toEqual(["Bearer old", "Bearer new"]);
    expect(await cli.get(device.id, device.ip, device.port)).toBe("new");
  } finally {
    globalThis.fetch = originalFetch;
    setTokenStoreForTesting(null);
    await rm(dir, { recursive: true, force: true });
  }
});
