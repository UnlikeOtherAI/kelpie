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

  it("registers 135 tools total (112 browser + 23 CLI)", () => {
    expect(browserTools).toHaveLength(112);
    expect(cliTools).toHaveLength(23);
    expect(browserTools.length + cliTools.length).toBe(135);
  });
});

describe("MCP tool routing logic", () => {
  beforeEach(() => {
    clearDevices();
  });

  it("getDevice returns undefined for unknown device", async () => {
    expect(await getDevice("nonexistent")).toBeUndefined();
  });

  it("getDevice resolves by name", async () => {
    addDevice(makeDevice());
    const d = await getDevice("TestPhone");
    expect(d).toBeDefined();
    expect(d!.id).toBe("test-device");
  });

  it("getDevice resolves by ID", async () => {
    addDevice(makeDevice());
    const d = await getDevice("test-device");
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
      makeDevice({ id: "d3", platform: "linux" }),
      makeDevice({ id: "d4", platform: "windows" }),
    ];
    const linux = filterDevices(devices, { platform: "linux" });
    expect(linux).toHaveLength(1);
    expect(linux[0].platform).toBe("linux");
  });
});
