import { afterEach, describe, expect, it, vi } from "vitest";
import { createPinnedCommandTransport } from "../../src/client/http-client.js";
import type { DiscoveredDevice } from "../../src/types.js";

afterEach(() => vi.unstubAllGlobals());
const device = (): DiscoveredDevice => ({
  id: "owned", name: "Owned", ip: "127.0.0.1", port: 8420, platform: "windows",
  model: "CEF", width: 800, height: 600, version: "test", lastSeen: 0, localControlToken: "initial-grant",
});
describe("pinned artifact transport", () => {
  it("retains one exact socket/grant and never pairs, falls back or follows redirects on rejection", async () => {
    const target = device();
    const fetcher = vi.fn(async () => new Response(JSON.stringify({ success: false }), { status: 401 }));
    vi.stubGlobal("fetch", fetcher);
    const send = await createPinnedCommandTransport(target);
    target.ip = "192.0.2.50";
    target.localControlToken = "replacement-grant";
    expect((await send("getScriptArtifact", { runId: "run", artifactId: "id" }, 1000)).status).toBe(401);
    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(fetcher).toHaveBeenCalledWith("http://127.0.0.1:8420/v1/get-script-artifact", expect.objectContaining({
      redirect: "error", headers: { "Content-Type": "application/json", Authorization: "Bearer initial-grant" },
    }));
  });
  it("bounds the response stream before JSON parsing", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({ data: "x".repeat(2_097_153) }), { status: 200 })));
    const send = await createPinnedCommandTransport(device());
    const response = await send("getScriptArtifact", { runId: "run", artifactId: "id" }, 1000);
    expect(response).toMatchObject({ ok: false, status: 0, data: { error: { message: "Pinned browser request failed" } } });
  });
});

it("never echoes malformed pinned response contents", async () => {
  vi.stubGlobal("fetch", vi.fn(async () => new Response('{"reflected":"private-response" invalid', { status: 200 })));
  const result = await (await createPinnedCommandTransport(device()))("getScriptStatus", { runId: "run" }, 1000);
  expect(result).toMatchObject({ ok: false, data: { error: { message: "Pinned browser request failed" } } });
  expect(JSON.stringify(result)).not.toContain("private-response");
});