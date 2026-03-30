import { describe, it, expect, beforeEach } from "vitest";
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
  beforeEach(() => {
    clearDevices();
  });

  it("adds and retrieves a device by ID", () => {
    const d = makeDevice();
    addDevice(d);
    expect(getDevice("test-uuid-1234")).toEqual(d);
  });

  it("retrieves by exact name", () => {
    addDevice(makeDevice());
    expect(getDevice("My iPhone")?.id).toBe("test-uuid-1234");
  });

  it("retrieves by fuzzy name (case-insensitive, substring)", () => {
    addDevice(makeDevice());
    expect(getDevice("iphone")?.id).toBe("test-uuid-1234");
  });

  it("retrieves by IP", () => {
    addDevice(makeDevice());
    expect(getDevice("192.168.1.42")?.id).toBe("test-uuid-1234");
  });

  it("returns undefined for unknown device", () => {
    expect(getDevice("nonexistent")).toBeUndefined();
  });

  it("prioritizes ID over name", () => {
    addDevice(makeDevice({ id: "abc", name: "abc" }));
    addDevice(makeDevice({ id: "def", name: "Different" }));
    expect(getDevice("abc")?.id).toBe("abc");
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
});
