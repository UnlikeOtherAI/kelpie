import { beforeEach, describe, expect, it, vi } from "vitest";
import { Command } from "commander";

vi.mock("../../src/discovery/local-probe.js", () => ({ probeHealth: vi.fn() }));
vi.mock("../../src/client/http-client.js", () => ({ sendCommand: vi.fn() }));
vi.mock("../../src/browser/store.js", () => ({
  getBrowserAlias: vi.fn(), loadBrowserStore: vi.fn(), readLocalReadiness: vi.fn(),
  readinessPath: vi.fn(), clearRunningBrowser: vi.fn(), removeBrowserAlias: vi.fn(),
  setRunningBrowser: vi.fn(), upsertBrowserAlias: vi.fn(),
}));

import { probeHealth } from "../../src/discovery/local-probe.js";
import { sendCommand } from "../../src/client/http-client.js";
import { registerBrowser } from "../../src/commands/browser.js";
import { clearRunningBrowser, getBrowserAlias, loadBrowserStore, readLocalReadiness, readinessPath } from "../../src/browser/store.js";

const readiness = { version: 1, launchId: "launch-a", deviceId: "device-a", port: 8420,
  token: "a".repeat(32), controlMode: "loopback" as const,
  mcp: { http: true, stdio: false, endpoint: "/mcp" as const } };

describe.each(["windows", "linux"] as const)("%s browser alias lifecycle", (platform) => {
  let currentReadiness: typeof readiness | undefined;
  const running = { win: { port: 8420, lastLaunchedAt: "2026-09-15T00:00:00.000Z", pid: 1234,
    launchId: "launch-a", readinessFile: "C:/profile/readiness.json", deviceId: "device-a" } };

  beforeEach(() => {
    vi.clearAllMocks();
    currentReadiness = readiness;
    vi.mocked(getBrowserAlias).mockResolvedValue({ platform, appPath: process.execPath, profileDir: "C:/profile" });
    vi.mocked(readinessPath).mockReturnValue("C:/profile/readiness.json");
    vi.mocked(readLocalReadiness).mockImplementation(async () => currentReadiness);
    vi.mocked(loadBrowserStore).mockImplementation(async () => ({ aliases: { win: { platform } }, running }));
    vi.mocked(probeHealth).mockResolvedValue(true);
    vi.mocked(sendCommand).mockImplementation(async () => {
      currentReadiness = undefined;
      return { ok: true, data: { success: true } } as never;
    });
    vi.mocked(clearRunningBrowser).mockResolvedValue();
    vi.spyOn(console, "log").mockImplementation(() => undefined);
    process.exitCode = undefined;
  });

  const program = () => { const command = new Command(); registerBrowser(command); return command; };

  it("preserves an existing live launch record when launch is repeated, then stops that same launch", async () => {
    await program().parseAsync(["node", "kelpie", "browser", "launch", "win"]);
    expect(clearRunningBrowser).not.toHaveBeenCalled();
    expect(process.exitCode).toBe(6);
    process.exitCode = undefined;
    await program().parseAsync(["node", "kelpie", "browser", "stop", "win"]);
    expect(sendCommand).toHaveBeenCalledOnce();
    expect(clearRunningBrowser).toHaveBeenCalledWith("win");
    expect(process.exitCode).toBeUndefined();
  });
});
