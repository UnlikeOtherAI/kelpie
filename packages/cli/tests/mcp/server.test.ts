import { describe, it, expect, beforeEach } from "vitest";
import { createMcpServer } from "../../src/mcp/server.js";
import { addDevice, clearDevices, getDevice, getAllDevices } from "../../src/discovery/registry.js";
import { filterDevices } from "../../src/group/filter.js";
import { browserTools, cliTools } from "../../src/mcp/tools.js";
import type { DiscoveredDevice } from "../../src/types.js";

function makeDevice(overrides: Partial<DiscoveredDevice> = {}): DiscoveredDevice {
  return {
    id: "test-device",
    name: "TestPhone",
    ip: "192.168.1.10",
    port: 8420,
    platform: "ios",
    model: "iPhone 15",
    width: 390,
    height: 844,
    version: "1.0.0",
    lastSeen: Date.now(),
    ...overrides,
  };
}

describe("createMcpServer", () => {
  it("creates a server instance", () => {
    const server = createMcpServer();
    expect(server).toBeDefined();
  });

  it("registers 103 tools total (83 browser + 20 CLI)", () => {
    expect(browserTools).toHaveLength(83);
    expect(cliTools).toHaveLength(20);
    expect(browserTools.length + cliTools.length).toBe(103);
  });
});

describe("MCP tool routing logic", () => {
  beforeEach(() => {
    clearDevices();
  });

  it("getDevice returns undefined for unknown device", () => {
    expect(getDevice("nonexistent")).toBeUndefined();
  });

  it("getDevice resolves by name", () => {
    addDevice(makeDevice());
    const d = getDevice("TestPhone");
    expect(d).toBeDefined();
    expect(d!.id).toBe("test-device");
  });

  it("getDevice resolves by ID", () => {
    addDevice(makeDevice());
    const d = getDevice("test-device");
    expect(d).toBeDefined();
  });

  it("getAllDevices returns registered devices", () => {
    addDevice(makeDevice({ id: "d1", name: "Phone1" }));
    addDevice(makeDevice({ id: "d2", name: "Phone2" }));
    expect(getAllDevices()).toHaveLength(2);
  });

  it("filter logic excludes devices by platform", () => {
    const devices = [
      makeDevice({ id: "d1", platform: "ios" }),
      makeDevice({ id: "d2", platform: "android" }),
    ];
    const ios = filterDevices(devices, { platform: "ios" });
    expect(ios).toHaveLength(1);
    expect(ios[0].platform).toBe("ios");
  });
});
