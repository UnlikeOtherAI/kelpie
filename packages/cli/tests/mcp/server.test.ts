import { describe, it, expect, beforeEach } from "vitest";
import { readFile, rm } from "node:fs/promises";
import { createMcpServer, formatBrowserToolResult } from "../../src/mcp/server.js";
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

  it("registers 142 tools total (118 browser + 24 CLI)", () => {
    expect(browserTools).toHaveLength(118);
    expect(cliTools).toHaveLength(24);
    expect(browserTools.length + cliTools.length).toBe(142);
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

describe("MCP browser result formatting", () => {
  it("saves native screenshots to a file and strips base64 from text output", async () => {
    const image = Buffer.from("native screenshot bytes").toString("base64");
    const result = await formatBrowserToolResult(
      "screenshot",
      {
        success: true,
        image,
        width: 3042,
        height: 2158,
        format: "png",
        resolution: "native",
      },
      "Test Mac",
    );

    const text = result.content.find((item) => item.type === "text");
    expect(text).toBeDefined();
    const metadata = JSON.parse(text!.text);
    expect(metadata).toMatchObject({
      success: true,
      width: 3042,
      height: 2158,
      format: "png",
      resolution: "native",
      imageSavedToFile: true,
      imageBytes: 23,
    });
    expect(metadata).not.toHaveProperty("image");
    expect(metadata.file).toContain("test-mac-");

    const resource = result.content.find((item) => item.type === "resource_link");
    expect(resource).toMatchObject({
      type: "resource_link",
      uri: expect.stringMatching(/^file:\/\//),
      mimeType: "image/png",
      size: 23,
    });
    expect(result.structuredContent).toEqual(metadata);
    await expect(readFile(metadata.file, "utf8")).resolves.toBe("native screenshot bytes");
    await rm(metadata.file, { force: true });
  });

  it("keeps viewport screenshots on the legacy text JSON path", async () => {
    const payload = {
      success: true,
      image: "abc",
      width: 390,
      height: 844,
      format: "png",
      resolution: "viewport",
    };
    const result = await formatBrowserToolResult("screenshot", payload, "Test Phone");

    expect(result.content).toEqual([{ type: "text", text: JSON.stringify(payload) }]);
    expect(result.structuredContent).toBeUndefined();
  });
});
