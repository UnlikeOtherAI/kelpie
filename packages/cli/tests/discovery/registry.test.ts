import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdtemp, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import {
  addDevice,
  addDevices,
  removeDevice,
  getDevice,
  getAllDevices,
  clearDevices,
  deviceCount,
} from "../../src/discovery/registry.js";
import type { DiscoveredDevice } from "../../src/types.js";
import { setRunningBrowser, upsertBrowserAlias } from "../../src/browser/store.js";

function makeDevice(overrides: Partial<DiscoveredDevice> = {}): DiscoveredDevice {
  return {
    id: "test-uuid-1234",
    name: "My iPhone",
    ip: "192.168.1.42",
    port: 8420,
    platform: "ios",
    model: "iPhone 15 Pro",
    width: 390,
    height: 844,
    version: "1.0.0",
    lastSeen: Date.now(),
    ...overrides,
  };
}

describe("device registry", () => {
  const originalHome = process.env.HOME;
  let homeDir = "";

  beforeEach(() => {
    clearDevices();
  });

  beforeEach(async () => {
    homeDir = await mkdtemp(path.join(os.tmpdir(), "kelpie-registry-"));
    process.env.HOME = homeDir;
  });

  afterEach(async () => {
    process.env.HOME = originalHome;
    await rm(homeDir, { recursive: true, force: true });
  });

  it("adds and retrieves a device by ID", async () => {
    const d = makeDevice();
    addDevice(d);
    expect(await getDevice("test-uuid-1234")).toEqual(d);
  });

  it("retrieves by exact name", async () => {
    addDevice(makeDevice());
    expect((await getDevice("My iPhone"))?.id).toBe("test-uuid-1234");
  });

  it("retrieves by fuzzy name (case-insensitive, substring)", async () => {
    addDevice(makeDevice());
    expect((await getDevice("iphone"))?.id).toBe("test-uuid-1234");
  });

  it("retrieves by IP", async () => {
    addDevice(makeDevice());
    expect((await getDevice("192.168.1.42"))?.id).toBe("test-uuid-1234");
  });

  it("returns undefined for unknown device", async () => {
    expect(await getDevice("nonexistent")).toBeUndefined();
  });

  it("prioritizes ID over name", async () => {
    addDevice(makeDevice({ id: "abc", name: "abc" }));
    addDevice(makeDevice({ id: "def", name: "Different" }));
    expect((await getDevice("abc"))?.id).toBe("abc");
  });

  it("adds multiple devices", () => {
    addDevices([
      makeDevice({ id: "a", name: "iPhone" }),
      makeDevice({ id: "b", name: "Pixel" }),
    ]);
    expect(deviceCount()).toBe(2);
  });

  it("removes a device", () => {
    addDevice(makeDevice());
    removeDevice("test-uuid-1234");
    expect(deviceCount()).toBe(0);
  });

  it("getAllDevices returns all", () => {
    addDevices([
      makeDevice({ id: "a", name: "A" }),
      makeDevice({ id: "b", name: "B" }),
      makeDevice({ id: "c", name: "C" }),
    ]);
    expect(getAllDevices()).toHaveLength(3);
  });

  it("clearDevices empties registry", () => {
    addDevices([
      makeDevice({ id: "a" }),
      makeDevice({ id: "b" }),
    ]);
    clearDevices();
    expect(deviceCount()).toBe(0);
  });

  it("resolves a launched local browser alias from ~/.kelpie", async () => {
    await upsertBrowserAlias("claude-a", { platform: "macos" });
    await setRunningBrowser("claude-a", {
      port: 8427,
      lastLaunchedAt: "2026-04-01T09:00:00.000Z",
    });

    const device = await getDevice("claude-a");
    expect(device?.ip).toBe("127.0.0.1");
    expect(device?.port).toBe(8427);
    expect(device?.platform).toBe("macos");
  });

  it("stores linux and windows devices without coercing their platform metadata", () => {
    addDevices([
      makeDevice({ id: "linux-1", platform: "linux", runtimeMode: "headless" }),
      makeDevice({ id: "windows-1", platform: "windows" }),
    ]);

    expect(getAllDevices()).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ id: "linux-1", platform: "linux", runtimeMode: "headless" }),
        expect.objectContaining({ id: "windows-1", platform: "windows" }),
      ]),
    );
  });
});
