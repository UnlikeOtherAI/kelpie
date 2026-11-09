import { mkdtemp, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { defaultDescribeDeps } from "../../src/commands/describe.js";
import { TokenStore, setTokenStoreForTesting, resetSessionCacheForTesting } from "../../src/auth/token-store.js";
import type { DiscoveredDevice } from "../../src/types.js";

let directory: string;
const device: DiscoveredDevice = { id: "computer", name: "Computer", ip: "127.0.0.1", port: 8420,
  platform: "macos", model: "Fixture", version: "0.1.36", width: 100, height: 100, lastSeen: 0 };

beforeEach(async () => {
  directory = await mkdtemp(path.join(os.tmpdir(), "kelpie-describe-computer-"));
  setTokenStoreForTesting(new TokenStore(path.join(directory, "tokens.json")));
  resetSessionCacheForTesting();
});
afterEach(async () => {
  setTokenStoreForTesting(null);
  resetSessionCacheForTesting();
  vi.unstubAllGlobals();
  await rm(directory, { recursive: true, force: true });
});

it.each([
  [{ approvalMode: "computer-key", requiresPairing: false }, true],
  [{ approvalMode: "computer-key", requiresPairing: true }, false],
  [{ requiresPairing: false }, false],
])("reports computer permission without creating another approval", async (info, paired) => {
  const request = vi.fn(async () => new Response(JSON.stringify(info)));
  vi.stubGlobal("fetch", request);
  expect(await defaultDescribeDeps("0.1.23").isPaired(device)).toBe(paired);
  expect(request).toHaveBeenCalledOnce();
  const [url, init] = request.mock.calls[0] as unknown as [string, RequestInit];
  expect(url).toBe("http://127.0.0.1:8420/v1/get-device-info");
  expect(new Headers(init.headers).has("Authorization")).toBe(false);
  expect(init.redirect).toBe("error");
});
