import { beforeEach, describe, expect, it, vi } from "vitest";

// `browser launch --port` shares its name with the program-wide `--port`, so
// this drives the real program parser rather than a bare `browser` command.
vi.mock("node:child_process", async (importOriginal) => ({
  ...(await importOriginal<typeof import("node:child_process")>()),
  spawn: vi.fn(),
}));
vi.mock("../../src/browser/store.js", () => ({
  getBrowserAlias: vi.fn(), loadBrowserStore: vi.fn(), readLocalReadiness: vi.fn(),
  readinessPath: vi.fn(), clearRunningBrowser: vi.fn(), removeBrowserAlias: vi.fn(),
  setRunningBrowser: vi.fn(), upsertBrowserAlias: vi.fn(),
}));

import { spawn } from "node:child_process";
import { getBrowserAlias, readLocalReadiness, readinessPath, setRunningBrowser } from "../../src/browser/store.js";
import { createProgram } from "../../src/program.js";

const readiness = { version: 1, launchId: "launch-b", deviceId: "device-a", port: 8441,
  token: "a".repeat(32), controlMode: "loopback" as const,
  mcp: { http: true, stdio: false, endpoint: "/mcp" as const } };

describe("browser launch port", () => {
  beforeEach(() => {
    vi.mocked(spawn).mockReset();
    vi.mocked(spawn).mockReturnValue({ exitCode: null, pid: 4321, once: vi.fn(), removeListener: vi.fn(), unref: vi.fn() } as never);
    vi.mocked(getBrowserAlias).mockResolvedValue({ platform: "windows", appPath: process.execPath, profileDir: "C:/profile" });
    vi.mocked(readinessPath).mockReturnValue("C:/profile/readiness.json");
    // No earlier launch, then the new launch's record.
    vi.mocked(readLocalReadiness).mockReset();
    vi.mocked(readLocalReadiness).mockResolvedValueOnce(undefined).mockResolvedValue(readiness);
    vi.mocked(setRunningBrowser).mockResolvedValue();
    vi.spyOn(console, "log").mockImplementation(() => undefined);
    process.exitCode = undefined;
  });

  it.each([
    ["after the alias", ["browser", "launch", "win", "--port", "8441"], 8441],
    ["before the command", ["--port", "8442", "browser", "launch", "win"], 8442],
    ["when omitted", ["browser", "launch", "win"], 8420],
  ])("uses --port %s", async (_placement, args, port) => {
    await createProgram("0.0.0-test").parseAsync(["node", "kelpie", ...args]);
    expect(process.exitCode).toBeUndefined();
    expect(spawn).toHaveBeenCalledOnce();
    expect(vi.mocked(spawn).mock.calls[0]?.[1]).toEqual(["--port", String(port), "--profile-dir", "C:/profile"]);
  });
});
