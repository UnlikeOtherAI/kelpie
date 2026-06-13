import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { mkdtemp, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { probeLocalDevices } from "../../src/discovery/local-probe.js";
import {
  addDevice,
  addDevices,
  removeDevice,
  getDevice,
  getAllDevices,
  clearDevices,
  deviceCount,
  TTL_MS,
} from "../../src/discovery/registry.js";
import type { DiscoveredDevice } from "../../src/types.js";
import { setRunningBrowser, upsertBrowserAlias } from "../../src/browser/store.js";

vi.mock("../../src/discovery/scanner.js", () => ({
  scanForDevices: vi.fn(async () => []),
}));

vi.mock("../../src/discovery/local-probe.js", () => ({
  probeLocalDevices: vi.fn(async () => []),
}));

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
    vi.mocked(probeLocalDevices).mockResolvedValue([]);
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

  it("resolves named localhost devices when mDNS is empty", async () => {
    vi.mocked(probeLocalDevices).mockResolvedValue([
      makeDevice({
        id: "local:127.0.0.1:8420",
        name: "dictator",
        ip: "127.0.0.1",
        port: 8420,
        platform: "macos",
      }),
    ]);

    const device = await getDevice("dictator");
    expect(device?.ip).toBe("127.0.0.1");
    expect(device?.platform).toBe("macos");
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

  it("evicts devices whose lastSeen is older than the mDNS TTL on read", async () => {
    const now = 1_000_000_000_000;
    vi.useFakeTimers();
    try {
      vi.setSystemTime(now);
      addDevice(makeDevice({ id: "fresh", name: "Fresh", lastSeen: now - (TTL_MS - 1000) }));
      addDevice(makeDevice({ id: "stale", name: "Stale", lastSeen: now - (TTL_MS + 1000) }));

      const all = getAllDevices();
      expect(all.map((d) => d.id).sort()).toEqual(["fresh"]);
      expect(deviceCount()).toBe(1);

      // Stale device must not be resolvable by name lookup either.
      expect(await getDevice("Stale")).toBeUndefined();
      expect((await getDevice("Fresh"))?.id).toBe("fresh");
    } finally {
      vi.useRealTimers();
    }
  });

  it("re-announcement refreshes lastSeen and prevents eviction", () => {
    const now = 1_000_000_000_000;
    vi.useFakeTimers();
    try {
      vi.setSystemTime(now);
      addDevice(makeDevice({ id: "d", lastSeen: now - (TTL_MS + 1000) }));
      // Re-announcement (same id, fresh lastSeen).
      addDevice(makeDevice({ id: "d", lastSeen: now }));
      expect(getAllDevices()).toHaveLength(1);
    } finally {
      vi.useRealTimers();
    }
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
