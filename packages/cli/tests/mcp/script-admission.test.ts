import { afterEach, expect, it, vi } from "vitest";
import { sendScriptPlayback } from "../../src/mcp/script-tools.js";
import type { DiscoveredDevice } from "../../src/types.js";
const io = vi.hoisted(() => ({ ordinary: vi.fn(), pinned: vi.fn(), pin: vi.fn() }));
vi.mock("../../src/client/http-client.js", () => ({ sendCommand: io.ordinary, createPinnedCommandTransport: io.pin }));
const device = { id: "fixture", ip: "127.0.0.1", port: 8420 } as DiscoveredDevice;
afterEach(() => vi.resetAllMocks());
it.each([undefined, [], [2], [1, 1], ["1"], [0, 1]])("refuses legacy/invalid strict support before any play: %j", async supportedVersions => {
  io.ordinary.mockResolvedValue({ ok: true, status: 200, data: { endpoints: ["get-script-artifact"] } });
  io.pin.mockResolvedValue(io.pinned);
  io.pinned.mockResolvedValue({ ok: true, status: 200, data: { success: true, playing: false, supportedVersions } });
  const result = await sendScriptPlayback(device, { version: 1, actions: [{ action: "click" }] }, 10000);
  expect(result.data).toMatchObject({ error: { code: "UNSUPPORTED_SCRIPT_VERSION" } });
  expect(io.pinned.mock.calls.map(call => call[0])).toEqual(["getScriptStatus"]);
  expect(io.ordinary.mock.calls.map(call => call[1])).toEqual(["getCapabilities"]);
});
it("uses the exact admitted pinned sender for strict playback", async () => {
  io.ordinary.mockResolvedValue({ ok: true, status: 200 });
  io.pin.mockResolvedValue(io.pinned);
  io.pinned.mockResolvedValueOnce({ ok: true, status: 200, data: { success: true, supportedVersions: [1] } })
    .mockResolvedValueOnce({ ok: true, status: 200, data: { success: true, runId: "run" } });
  await sendScriptPlayback(device, { version: 1, actions: [] }, 1234);
  expect(io.pin).toHaveBeenCalledOnce();
  expect(io.pinned.mock.calls.map(call => call[0])).toEqual(["getScriptStatus", "playScript"]);
  expect(io.pinned.mock.calls[1]?.[2]).toBe(1234);
});
it("preserves unversioned legacy playback without capability probes or pinning", async () => {
  io.ordinary.mockResolvedValue({ ok: true, status: 200, data: { success: true } });
  await sendScriptPlayback(device, { actions: [] }, 10000);
  expect(io.ordinary).toHaveBeenCalledWith(device, "playScript", { actions: [] }, 10000);
  expect(io.pin).not.toHaveBeenCalled();
});
