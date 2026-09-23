import { describe, it, expect, beforeEach } from "vitest";
import { readFile, rm } from "node:fs/promises";
import { createMcpServer, formatBrowserToolResult } from "../../src/mcp/server.js";
import { addDevice, clearDevices, getDevice, getAllDevices } from "../../src/discovery/registry.js";
import { filterDevices } from "../../src/group/filter.js";
import { browserTools, cliTools } from "../../src/mcp/tools.js";
import { BrowserMcpTools, CliMcpTools } from "../../../shared/src/index.js";
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

  it("registers exactly the shared browser and CLI catalogues", () => {
    expect(browserTools.map((tool) => tool.name)).toEqual([...BrowserMcpTools]);
    expect(cliTools.map((tool) => tool.name)).toEqual([...CliMcpTools]);
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
      { name: "Test Mac" },
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
    expect(result.content.find((item) => item.type === "image")).toMatchObject({
      type: "image",
      data: image,
      mimeType: "image/png",
    });
    await expect(readFile(metadata.file, "utf8")).resolves.toBe("native screenshot bytes");
    await rm(metadata.file, { force: true });
  });

  it("sends a portable screenshot's base64 exactly once, as the image item", async () => {
    const image = Buffer.from("portable screenshot bytes!").toString("base64");
    const payload = {
      success: true,
      image,
      width: 390,
      height: 844,
      format: "png",
      resolution: "viewport",
      tab: { id: "tab-1" },
    };
    const result = await formatBrowserToolResult("screenshot", payload, { name: "Test Windows" });

    const { image: _image, ...rest } = payload;
    const metadata = { ...rest, mimeType: "image/png", imageBytes: 26 };
    expect(result.content).toEqual([
      { type: "text", text: JSON.stringify(metadata) },
      { type: "image", data: image, mimeType: "image/png" },
    ]);
    expect(result.structuredContent).toEqual(metadata);
    expect(JSON.stringify(result).split(image)).toHaveLength(2);
  });

  it("reports a JPEG screenshot's MIME type and decoded size", async () => {
    const image = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00]).toString("base64");
    const result = await formatBrowserToolResult(
      "screenshot",
      { success: true, image, width: 960, height: 479, format: "jpeg" },
      {},
      { format: "jpeg", maxWidth: 960 },
    );

    expect(result.isError).toBeUndefined();
    expect(result.structuredContent).toMatchObject({ format: "jpeg", mimeType: "image/jpeg", imageBytes: 5 });
    expect(result.structuredContent).not.toHaveProperty("image");
    expect(result.content[1]).toEqual({ type: "image", data: image, mimeType: "image/jpeg" });
  });

  it("refuses an image wider than the requested maxWidth instead of sending it", async () => {
    const image = "iVBORw0KGgo=";
    const result = await formatBrowserToolResult(
      "screenshot",
      { success: true, image, width: 1918, height: 957, format: "png" },
      { name: "probe", platform: "windows" },
      { maxWidth: 960 },
    );

    expect(result.isError).toBe(true);
    expect(JSON.stringify(result)).not.toContain(image);
    const body = JSON.parse((result.content[0] as { text: string }).text);
    expect(body.error).toMatchObject({ code: "SCREENSHOT_OPTION_UNSUPPORTED", option: "maxWidth" });
    expect(body.error.message).toContain("\"probe\" (windows)");
    expect(body.error.message).toContain("1918 px");
  });

  it("applies the page-text ceiling to kelpie_get_page_text results", async () => {
    const result = await formatBrowserToolResult(
      "getPageText",
      { success: true, mode: "readable", text: "x".repeat(30), length: 30 },
      {},
      { maxChars: 10 },
    );

    const body = JSON.parse((result.content[0] as { text: string }).text);
    expect(body).toMatchObject({ text: "x".repeat(10), truncated: true, totalChars: 30, length: 30 });
  });

  it("marks browser-control failures as MCP errors", async () => {
    const result = await formatBrowserToolResult("navigate", {
      success: false,
      error: { code: "TAB_REQUIRED", message: "tabId is required" },
    });

    expect(result.isError).toBe(true);
    expect(result.content).toEqual([{
      type: "text",
      text: JSON.stringify({ success: false, error: { code: "TAB_REQUIRED", message: "tabId is required" } }),
    }]);
  });
});
