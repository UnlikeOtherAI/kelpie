import { beforeEach, describe, expect, it, vi } from "vitest";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import type { DiscoveredDevice } from "../../src/types.js";

const { scanForDevices, probeLocalDevices } = vi.hoisted(() => ({ scanForDevices: vi.fn(), probeLocalDevices: vi.fn() }));
vi.mock("../../src/discovery/scanner.js", () => ({ scanForDevices }));
vi.mock("../../src/discovery/local-probe.js", () => ({ probeLocalDevices }));
vi.mock("../../src/discovery/capabilities.js", () => ({
  enrichDevicesWithCapabilities: async (devices: DiscoveredDevice[]) => devices,
}));

const { createMcpServer } = await import("../../src/mcp/server.js");
const { clearDevices } = await import("../../src/discovery/registry.js");

function device(overrides: Partial<DiscoveredDevice>): DiscoveredDevice {
  return {
    id: "d",
    name: "d",
    ip: "127.0.0.1",
    port: 8420,
    platform: "windows",
    model: "Kelpie windows",
    width: 0,
    height: 0,
    version: "0.1.1",
    lastSeen: Date.now(),
    ...overrides,
  };
}

async function discover(): Promise<{ count: number; devices: DiscoveredDevice[] }> {
  const server = createMcpServer();
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  const client = new Client({ name: "discover-test", version: "1" });
  await Promise.all([server.connect(serverTransport), client.connect(clientTransport)]);
  try {
    const result = await client.callTool({ name: "kelpie_discover", arguments: { timeout: 10 } });
    return JSON.parse((result.content as { text: string }[])[0]!.text);
  } finally {
    await client.close();
  }
}

describe("kelpie_discover", () => {
  beforeEach(() => {
    clearDevices();
    scanForDevices.mockReset();
    probeLocalDevices.mockReset();
  });

  it("finds a loopback-only browser that never announces itself on mDNS", async () => {
    scanForDevices.mockResolvedValue([]);
    probeLocalDevices.mockResolvedValue([device({ id: "local:127.0.0.1:8420", name: "probe" })]);

    const result = await discover();

    expect(scanForDevices).toHaveBeenCalledWith(10);
    expect(result.count).toBe(1);
    expect(result.devices[0]).toMatchObject({ id: "local:127.0.0.1:8420", platform: "windows" });
  });

  it("does not probe loopback when the mDNS browse found devices", async () => {
    scanForDevices.mockResolvedValue([device({ id: "phone", ip: "192.168.1.20", platform: "ios" })]);

    const result = await discover();

    expect(probeLocalDevices).not.toHaveBeenCalled();
    expect(result.devices.map((found) => found.id)).toEqual(["phone"]);
  });
});
