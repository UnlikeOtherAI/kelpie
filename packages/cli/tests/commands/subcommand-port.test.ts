import { EventEmitter } from "node:events";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { CLI_MCP_PORT } from "@unlikeotherai/kelpie-shared";

vi.mock("node:child_process", () => ({ spawn: vi.fn(), execFile: vi.fn() }));
// What the machine happens to have listening must not decide these results.
vi.mock("../../src/browser/launch.js", () => ({ allocateBrowserPort: vi.fn() }));
vi.mock("../../src/discovery/local-probe.js", () => ({ probeHealth: vi.fn() }));
vi.mock("../../src/browser/store.js", () => ({
  getBrowserAlias: vi.fn(), loadBrowserStore: vi.fn(), readLocalReadiness: vi.fn(),
  readinessPath: vi.fn(), clearRunningBrowser: vi.fn(), removeBrowserAlias: vi.fn(),
  setRunningBrowser: vi.fn(), upsertBrowserAlias: vi.fn(),
}));
vi.mock("../../src/mcp/server.js", () => ({ createMcpServer: vi.fn(() => ({})) }));
vi.mock("../../src/mcp/transport.js", () => ({
  DEFAULT_MCP_BIND_HOST: "127.0.0.1", startHttp: vi.fn(), startStdio: vi.fn(),
}));

import { execFile, spawn } from "node:child_process";
import { allocateBrowserPort } from "../../src/browser/launch.js";
import { probeHealth } from "../../src/discovery/local-probe.js";
import { getBrowserAlias, readLocalReadiness, readinessPath } from "../../src/browser/store.js";
import { startHttp } from "../../src/mcp/transport.js";
import { createProgram } from "../../src/program.js";

// The real program, not a bare Command: the defect only exists because the
// program declares a global `--port` that commander hands every `--port` to.
const run = (...args: string[]) => createProgram("0.0.0-test").parseAsync(["node", "kelpie", ...args]);

function launchChild(): EventEmitter & { exitCode: null; pid: number; unref: () => void } {
  return Object.assign(new EventEmitter(), { exitCode: null, pid: 4321, unref: () => undefined });
}

describe("browser launch --port on Windows", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(getBrowserAlias).mockResolvedValue({ platform: "windows", appPath: process.execPath, profileDir: "C:/profile" });
    vi.mocked(readinessPath).mockReturnValue("C:/profile/readiness.json");
    vi.mocked(spawn).mockImplementation(() => launchChild() as never);
    vi.mocked(allocateBrowserPort).mockResolvedValue(8424);
    // No readiness before the launch; the new instance's record once spawned.
    vi.mocked(readLocalReadiness).mockImplementation(async () => (vi.mocked(spawn).mock.calls.length === 0 ? undefined : {
      version: 1, launchId: "launch-new", deviceId: "device-new", port: 8467, token: "a".repeat(32),
      controlMode: "loopback" as const, mcp: { http: true, stdio: false, endpoint: "/mcp" as const },
    }));
    vi.spyOn(console, "log").mockImplementation(() => undefined);
    process.exitCode = undefined;
  });

  const spawnedArgs = () => vi.mocked(spawn).mock.calls[0]?.[1];

  it("spawns the app on the port given after the subcommand", async () => {
    await run("browser", "launch", "x", "--port", "8467");
    expect(spawnedArgs()).toEqual(["--port", "8467", "--profile-dir", "C:/profile"]);
    expect(process.exitCode).toBeUndefined();
  });

  it("spawns the app on the port given before the subcommand", async () => {
    await run("--port", "8467", "browser", "launch", "x");
    expect(spawnedArgs()).toEqual(["--port", "8467", "--profile-dir", "C:/profile"]);
  });

  it("launches on the first free port when none is given", async () => {
    await run("browser", "launch", "x");
    expect(allocateBrowserPort).toHaveBeenCalledOnce();
    expect(spawnedArgs()).toEqual(["--port", "8424", "--profile-dir", "C:/profile"]);
  });

  it("uses an explicit port exactly, the reserved one included, without probing", async () => {
    await run("browser", "launch", "x", "--port", "8421");
    expect(allocateBrowserPort).not.toHaveBeenCalled();
    expect(spawnedArgs()).toEqual(["--port", "8421", "--profile-dir", "C:/profile"]);
  });

  it("fails the launch rather than spawning when no port is free", async () => {
    vi.mocked(allocateBrowserPort).mockRejectedValue(new Error("No free port from 8420 to 8519"));
    await run("browser", "launch", "x");
    expect(spawn).not.toHaveBeenCalled();
    expect(process.exitCode).toBe(6);
    expect(vi.mocked(console.log).mock.calls.join("\n")).toContain("BROWSER_LAUNCH_FAILED");
  });

  it("rejects a port that is not a port instead of launching on the default", async () => {
    await run("browser", "launch", "x", "--port", "http");
    expect(spawn).not.toHaveBeenCalled();
    expect(process.exitCode).toBe(4);
  });
});

describe("browser launch --port on macOS", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(getBrowserAlias).mockResolvedValue({ platform: "macos", appPath: process.execPath });
    let opened = false;
    vi.mocked(execFile).mockImplementation(((_file: string, _args: string[], callback: (error: null, result: object) => void) => {
      opened = true;
      callback(null, { stdout: "", stderr: "" });
    }) as never);
    vi.mocked(probeHealth).mockImplementation(async (port: number) => opened && (port === 8467 || port === 8424));
    vi.mocked(allocateBrowserPort).mockResolvedValue(8424);
    vi.spyOn(console, "log").mockImplementation(() => undefined);
    process.exitCode = undefined;
  });

  it("opens the app on the port given after the subcommand", async () => {
    await run("browser", "launch", "x", "--port", "8467");
    expect(vi.mocked(execFile).mock.calls[0]?.slice(0, 2)).toEqual(["open", ["-na", process.execPath, "--args", "--port", "8467"]]);
  });

  it("opens the app on the first free port when none is given", async () => {
    await run("browser", "launch", "x");
    expect(vi.mocked(execFile).mock.calls[0]?.slice(0, 2)).toEqual(["open", ["-na", process.execPath, "--args", "--port", "8424"]]);
  });
});

describe("mcp --http --port", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    process.exitCode = undefined;
  });

  const servedPort = () => vi.mocked(startHttp).mock.calls[0]?.[1];

  it("serves on the port given after the subcommand", async () => {
    await run("mcp", "--http", "--port", "9000");
    expect(servedPort()).toBe(9000);
  });

  it("keeps its own default rather than the program's device port", async () => {
    await run("mcp", "--http");
    expect(servedPort()).toBe(CLI_MCP_PORT);
  });
});
