import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { nativeBrowserTransport } from "../../src/client/browser-control.js";
import { TokenStore, setTokenStoreForTesting, resetSessionCacheForTesting } from "../../src/auth/token-store.js";
import type { DiscoveredDevice } from "../../src/types.js";

const device: DiscoveredDevice = { id: "native", name: "Browser", ip: "192.168.1.42", port: 8420,
  platform: "ios", model: "iPhone", width: 390, height: 844, version: "test", lastSeen: Date.now() };
const challenge = "c".repeat(43), token = "t".repeat(43);
let directory: string;
let store: TokenStore;
let calls: { url: string; init: RequestInit }[];

function mockResponses(values: { status: number; body: object }[]) {
  vi.stubGlobal("fetch", vi.fn(async (url: string, init: RequestInit) => {
    calls.push({ url, init });
    const next = values.shift();
    if (!next) throw new Error("Unexpected request");
    return new Response(JSON.stringify(next.body), { status: next.status });
  }));
}
const unauthorized = { status: 401, body: { success: false } };
const offered = () => ({ status: 202, body: { status: "account_challenge", requestId: challenge, expiresAt: Date.now() + 120_000 } });

describe("account authorization through the compact MCP browser transport", () => {
  beforeEach(async () => {
    directory = await mkdtemp(join(tmpdir(), "kelpie-account-core-"));
    store = new TokenStore(directory);
    setTokenStoreForTesting(store);
    resetSessionCacheForTesting();
    calls = [];
    vi.spyOn(process.stderr, "write").mockImplementation(() => true);
  });
  afterEach(async () => {
    setTokenStoreForTesting(null);
    resetSessionCacheForTesting();
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
    await rm(directory, { recursive: true, force: true });
  });

  it("automatically authorizes the same account and reuses only the memory grant", async () => {
    vi.stubEnv("KELPIE_UOA_ACCESS_TOKEN", "existing-account-session");
    const answer = { version: 1, ok: true, value: [] };
    mockResponses([unauthorized, offered(), { status: 200, body: { pairing_ticket: "narrow-proof" } },
      { status: 200, body: { status: "approved", scope: "session", token, expiresAt: Date.now() + 60_000 } },
      { status: 200, body: answer }, { status: 200, body: answer }]);
    const transport = nativeBrowserTransport(device);
    expect(await transport.call({ version: 1, method: "tabs.list", params: {} })).toEqual(answer);
    expect(await transport.call({ version: 1, method: "tabs.list", params: {} })).toEqual(answer);
    expect(calls).toHaveLength(6);
    expect(calls[2].url).toBe("https://authentication.unlikeotherai.com/oauth/kelpie/pair");
    for (const call of calls.filter(call => call.url.startsWith("http:"))) {
      expect(JSON.stringify(call.init)).not.toContain("existing-account-session");
    }
    expect(new Headers(calls[5].init.headers).get("Authorization")).toBe(`Bearer ${token}`);
    expect(await store.list()).toEqual({});
    expect(process.stderr.write).not.toHaveBeenCalled();
  });

  it("does not open a manual pairing request when no account is available", async () => {
    vi.stubEnv("KELPIE_UOA_ACCESS_TOKEN", "");
    mockResponses([unauthorized]);
    const answer = await nativeBrowserTransport(device).call({ version: 1, method: "tabs.list", params: {} });
    expect(answer).toMatchObject({ ok: false, error: { code: "ACCESS_DENIED", mayHaveCompleted: false } });
    expect(calls).toHaveLength(1);
    expect(process.stderr.write).not.toHaveBeenCalled();
  });

  it("refuses invalid account proof without downgrading to a manual prompt", async () => {
    vi.stubEnv("KELPIE_UOA_ACCESS_TOKEN", "existing-account-session");
    mockResponses([unauthorized, offered(), { status: 403, body: { error: "Request failed" } }]);
    const answer = await nativeBrowserTransport(device).call({ version: 1, method: "tabs.list", params: {} });
    expect(answer).toMatchObject({ ok: false, error: { code: "ACCESS_DENIED" } });
    expect(calls.filter(call => call.url.endsWith("/v1/pair"))).toHaveLength(1);
    expect(await store.list()).toEqual({});
  });
});
