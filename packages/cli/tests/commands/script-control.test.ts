import { afterEach, describe, expect, it, vi } from "vitest";
import { Command } from "commander";
import { controlScriptRun } from "../../src/commands/script-run.js";
const mocks = vi.hoisted(() => ({ send: vi.fn(), pin: vi.fn(), ordinary: vi.fn(), legacy: vi.fn(), print: vi.fn() }));
const target = vi.hoisted(() => ({ id: "browser", ip: "127.0.0.1", port: 8420 }));
vi.mock("../../src/client/http-client.js", () => ({ createPinnedCommandTransport: mocks.pin, sendCommand: mocks.ordinary }));
vi.mock("../../src/commands/helpers.js", () => ({
  getGlobals: () => ({ format: "json" }), requireDevice: async () => target,
  commandTimeout: () => 1000, deviceCommand: mocks.legacy,
}));
vi.mock("../../src/output/formatter.js", () => ({ print: mocks.print }));
afterEach(() => { vi.clearAllMocks(); process.exitCode = undefined; });
describe("run-owned script controls", () => {
  it.each(["getScriptStatus", "abortScript"] as const)("pins %s once and refuses authorization failure without fallback", async method => {
    mocks.pin.mockResolvedValue(mocks.send);
    mocks.send.mockResolvedValue({ ok: false, status: 401, data: { success: false } });
    await controlScriptRun(new Command(), method, "run");
    expect(mocks.pin).toHaveBeenCalledWith(target);
    expect(mocks.send).toHaveBeenCalledOnce();
    expect(mocks.send).toHaveBeenCalledWith(method, { runId: "run" }, 1000);
    expect(mocks.ordinary).not.toHaveBeenCalled();
    expect(mocks.legacy).not.toHaveBeenCalled();
  });
  it("keeps the unversioned control path unchanged", async () => {
    await controlScriptRun(new Command(), "getScriptStatus");
    expect(mocks.legacy).toHaveBeenCalledOnce();
    expect(mocks.pin).not.toHaveBeenCalled();
  });
});

it("supports pinned timeout recovery before the run ID is known", async () => {
  mocks.pin.mockResolvedValue(mocks.send);
  mocks.send.mockResolvedValue({ ok: true, status: 200, data: { success: true } });
  await controlScriptRun(new Command(), "getScriptStatus", undefined, true);
  expect(mocks.send).toHaveBeenCalledWith("getScriptStatus", {}, 1000);
  expect(mocks.legacy).not.toHaveBeenCalled();
  expect(mocks.ordinary).not.toHaveBeenCalled();
});