import { afterEach, describe, expect, it } from "vitest";
import net from "node:net";
import { DEFAULT_PORT } from "@unlikeotherai/kelpie-shared";
import { allocateBrowserPort, isPortFree, resolveAppPath, validateBrowserName } from "../../src/browser/launch.js";

/** A probe that reports exactly the given ports as taken. */
const takenPorts = (...taken: number[]) => async (port: number) => !taken.includes(port);

describe("browser launch helpers", () => {
  let busyServer: net.Server | null = null;

  afterEach(async () => {
    const server = busyServer;
    busyServer = null;
    if (server) await new Promise<void>((resolve) => { server.close(() => { resolve(); }); });
  });

  it("validates browser alias names", () => {
    expect(validateBrowserName("claude-a")).toBe(true);
    expect(validateBrowserName("codex_2")).toBe(true);
    expect(validateBrowserName("bad name")).toBe(false);
  });

  it("allocates the default port when it is free", async () => {
    expect(await allocateBrowserPort(takenPorts())).toBe(DEFAULT_PORT);
  });

  it("skips an occupied port and never hands out the AppReveal and CLI MCP port", async () => {
    // 8421 is free here, so only the reservation keeps the scan off it.
    expect(await allocateBrowserPort(takenPorts(8420))).toBe(8422);
  });

  it("fails rather than falling back to a taken port when the range is full", async () => {
    await expect(allocateBrowserPort(async () => false)).rejects.toThrow("No free port");
  });

  it("probes by binding the loopback address", async () => {
    busyServer = net.createServer();
    const port = await new Promise<number>((resolve) => {
      busyServer!.listen(0, "127.0.0.1", () => { resolve((busyServer!.address() as net.AddressInfo).port); });
    });
    expect(await isPortFree(port)).toBe(false);
  });

  it("returns null when Kelpie.app is not installed", () => {
    expect(resolveAppPath({ platform: "macos", appPath: "/does/not/exist/Kelpie.app" })).toBeNull();
  });
});
