import { describe, it, expect, beforeAll } from "vitest";
import { testDevice, isDeviceReachable } from "./setup.js";
import { BrowserMcpTools, CliMcpTools } from "@unlikeotherai/kelpie-shared";

/**
 * MCP tool definition tests — verify all tools are correctly defined
 * and match the shared constants. These don't require a real device.
 */
describe("E2E: MCP Tool Definitions", () => {
  it("browser MCP tools cover all expected methods", () => {
    expect(BrowserMcpTools.length).toBe(92);
    // Spot check key tools
    expect(BrowserMcpTools).toContain("kelpie_navigate");
    expect(BrowserMcpTools).toContain("kelpie_screenshot");
    expect(BrowserMcpTools).toContain("kelpie_click");
    expect(BrowserMcpTools).toContain("kelpie_get_accessibility_tree");
    expect(BrowserMcpTools).toContain("kelpie_get_page_text");
    expect(BrowserMcpTools).toContain("kelpie_get_viewport_presets");
    expect(BrowserMcpTools).toContain("kelpie_set_viewport_preset");
  });

  it("CLI MCP tools cover all expected methods", () => {
    expect(CliMcpTools.length).toBe(20);
    expect(CliMcpTools).toContain("kelpie_discover");
    expect(CliMcpTools).toContain("kelpie_group_navigate");
    expect(CliMcpTools).toContain("kelpie_list_devices");
  });

  it("total MCP tools is 112", () => {
    expect(BrowserMcpTools.length + CliMcpTools.length).toBe(112);
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
