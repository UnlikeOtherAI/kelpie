import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { mkdtemp, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { DEFAULT_PORT } from "@unlikeotherai/kelpie-shared";
import { probeHealth, probeLocalDevices } from "../../src/discovery/local-probe.js";
import { setRunningBrowser, upsertBrowserAlias } from "../../src/browser/store.js";

/** Stub fetch so only the given localhost ports answer /health with 200. */
function stubReachablePorts(ports: number[]): void {
  vi.stubGlobal(
    "fetch",
    vi.fn(async (url: string | URL | Request) => {
      const target = String(url);
      const ok = ports.some((port) => target.includes(`:${port}/health`));
      if (!ok) {
        throw new Error("connection refused");
      }
      return new Response("ok", { status: 200 });
    }),
  );
}

describe("local-probe", () => {
  const originalHome = process.env.HOME;
  let homeDir = "";

  beforeEach(async () => {
    homeDir = await mkdtemp(path.join(os.tmpdir(), "kelpie-local-probe-"));
    process.env.HOME = homeDir;
  });

  afterEach(async () => {
    vi.unstubAllGlobals();
    process.env.HOME = originalHome;
    await rm(homeDir, { recursive: true, force: true });
  });

  describe("probeHealth", () => {
    it("returns true when /health responds ok", async () => {
      stubReachablePorts([DEFAULT_PORT]);
      expect(await probeHealth(DEFAULT_PORT)).toBe(true);
    });

    it("returns false when fetch rejects", async () => {
      stubReachablePorts([]);
      expect(await probeHealth(DEFAULT_PORT)).toBe(false);
    });

    it("returns false when the response is not ok", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn(async () => new Response("nope", { status: 503 })),
      );
      expect(await probeHealth(DEFAULT_PORT)).toBe(false);
    });
  });

  describe("probeLocalDevices", () => {
    it("returns a device for each reachable default-range port", async () => {
      stubReachablePorts([DEFAULT_PORT]);
      const devices = await probeLocalDevices();
      expect(devices).toHaveLength(1);
      const [device] = devices;
      expect(device.id).toBe(`local:127.0.0.1:${DEFAULT_PORT}`);
      expect(device.ip).toBe("127.0.0.1");
      expect(device.port).toBe(DEFAULT_PORT);
      expect(device.name).toBe(`localhost:${DEFAULT_PORT}`);
      expect(device.platform).toBe("macos");
    });

    it("skips unreachable ports", async () => {
      stubReachablePorts([]);
      expect(await probeLocalDevices()).toEqual([]);
    });

    it("includes ports recorded in the browser store", async () => {
      const storePort = DEFAULT_PORT + 50; // outside the default sweep range
      await upsertBrowserAlias("claude-a", { platform: "macos" });
      await setRunningBrowser("claude-a", {
        port: storePort,
        lastLaunchedAt: "2026-04-01T09:00:00.000Z",
      });
      stubReachablePorts([storePort]);

      const devices = await probeLocalDevices();
      expect(devices).toHaveLength(1);
      const [device] = devices;
      expect(device.port).toBe(storePort);
      // The matching alias supplies name + platform.
      expect(device.name).toBe("claude-a");
      expect(device.platform).toBe("macos");
    });

    it("dedupes when a stored running port overlaps the default sweep", async () => {
      await upsertBrowserAlias("claude-a", { platform: "macos" });
      await setRunningBrowser("claude-a", {
        port: DEFAULT_PORT,
        lastLaunchedAt: "2026-04-01T09:00:00.000Z",
      });
      stubReachablePorts([DEFAULT_PORT]);

      const devices = await probeLocalDevices();
      expect(devices).toHaveLength(1);
      expect(devices[0].port).toBe(DEFAULT_PORT);
      expect(devices[0].name).toBe("claude-a");
    });
  });
});
