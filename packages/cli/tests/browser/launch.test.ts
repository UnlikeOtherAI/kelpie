import { afterEach, beforeEach, describe, expect, it } from "vitest";
import net from "node:net";
import { allocateBrowserPort, resolveAppPath, validateBrowserName } from "../../src/browser/launch.js";

describe("browser launch helpers", () => {
  let busyServer: net.Server | null = null;

  beforeEach(() => {
    busyServer = null;
  });

  afterEach(async () => {
    await new Promise<void>((resolve) => {
      if (!busyServer) {
        resolve();
        return;
      }
      busyServer.close(() => resolve());
    });
  });

  it("validates browser alias names", () => {
    expect(validateBrowserName("claude-a")).toBe(true);
    expect(validateBrowserName("codex_2")).toBe(true);
    expect(validateBrowserName("bad name")).toBe(false);
  });

  it("rejects the AppReveal and CLI MCP reserved port", async () => {
    await expect(allocateBrowserPort(8421)).rejects.toThrow("reserved");
  });

  it("skips an occupied port during automatic allocation", async () => {
    busyServer = net.createServer();
    await new Promise<void>((resolve) => {
      busyServer!.listen(8420, "127.0.0.1", () => resolve());
    });

    const port = await allocateBrowserPort();
    expect(port).not.toBe(8420);
    expect(port).not.toBe(8421);
  });

  it("returns null when Mollotov.app is not installed", () => {
    expect(resolveAppPath({ platform: "macos", appPath: "/does/not/exist/Mollotov.app" })).toBeNull();
  });
});
