import { describe, it, expect, beforeAll } from "vitest";
import { testDevice, isDeviceReachable } from "./setup.js";
import { BrowserMcpTools, CliMcpTools } from "@unlikeotherai/mollotov-shared";

/**
 * MCP tool definition tests — verify all tools are correctly defined
 * and match the shared constants. These don't require a real device.
 */
describe("E2E: MCP Tool Definitions", () => {
  it("browser MCP tools cover all expected methods", () => {
    expect(BrowserMcpTools.length).toBe(79);
    // Spot check key tools
    expect(BrowserMcpTools).toContain("mollotov_navigate");
    expect(BrowserMcpTools).toContain("mollotov_screenshot");
    expect(BrowserMcpTools).toContain("mollotov_click");
    expect(BrowserMcpTools).toContain("mollotov_get_accessibility_tree");
    expect(BrowserMcpTools).toContain("mollotov_get_page_text");
  });

  it("CLI MCP tools cover all expected methods", () => {
    expect(CliMcpTools.length).toBe(20);
    expect(CliMcpTools).toContain("mollotov_discover");
    expect(CliMcpTools).toContain("mollotov_group_navigate");
    expect(CliMcpTools).toContain("mollotov_list_devices");
  });

  it("total MCP tools is 99", () => {
    expect(BrowserMcpTools.length + CliMcpTools.length).toBe(99);
  });
});

describe("E2E: MCP Server Endpoint", () => {
  const device = testDevice();
  let reachable = false;

  beforeAll(async () => {
    reachable = await isDeviceReachable(device);
  });

  it("device returns valid JSON for all standard methods", async () => {
    if (!reachable) return;
    // Test a representative set of methods that should always succeed
    const methods = [
      "get-device-info",
      "get-capabilities",
      "get-viewport",
      "get-console-messages",
      "get-js-errors",
      "get-tabs",
      "get-iframes",
      "get-shadow-roots",
    ];
    for (const method of methods) {
      const url = `http://${device.ip}:${device.port}/v1/${method}`;
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: "{}",
      });
      expect(res.ok, `${method} should return 200`).toBe(true);
      const data = await res.json();
      expect(data, `${method} should have success field`).toHaveProperty("success");
    }
  });
});
