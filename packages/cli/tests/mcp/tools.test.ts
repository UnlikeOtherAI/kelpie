import { describe, it, expect } from "vitest";
import { browserTools, cliTools } from "../../src/mcp/tools.js";
import { BrowserMcpTools, CliMcpTools } from "@unlike-other-ai/mollotov-shared";

describe("MCP tool definitions", () => {
  it("has correct number of browser tools", () => {
    expect(browserTools).toHaveLength(BrowserMcpTools.length);
  });

  it("has correct number of CLI tools", () => {
    expect(cliTools).toHaveLength(CliMcpTools.length);
  });

  it("browser tool names match shared constants exactly", () => {
    const toolNames = browserTools.map((t) => t.name);
    expect(toolNames).toEqual([...BrowserMcpTools]);
  });

  it("CLI tool names match shared constants exactly", () => {
    const toolNames = cliTools.map((t) => t.name);
    expect(toolNames).toEqual([...CliMcpTools]);
  });

  it("all browser tools have device in schema", () => {
    for (const tool of browserTools) {
      expect(tool.schema).toHaveProperty("device");
    }
  });

  it("all browser tools have a description", () => {
    for (const tool of browserTools) {
      expect(tool.description.length).toBeGreaterThan(0);
    }
  });

  it("all CLI tools have a description", () => {
    for (const tool of cliTools) {
      expect(tool.description.length).toBeGreaterThan(0);
    }
  });

  it("group tools have filter properties", () => {
    const groupTools = cliTools.filter((t) => t.kind === "group" || t.kind === "smartQuery");
    for (const tool of groupTools) {
      expect(tool.schema).toHaveProperty("platform");
      expect(tool.schema).toHaveProperty("include");
      expect(tool.schema).toHaveProperty("exclude");
    }
  });

  it("group tools do NOT have device property", () => {
    for (const tool of cliTools) {
      expect(tool.schema).not.toHaveProperty("device");
    }
  });

  it("all tool names use mollotov_ prefix", () => {
    for (const tool of [...browserTools, ...cliTools]) {
      expect(tool.name).toMatch(/^mollotov_/);
    }
  });

  it("all tool names use underscores not hyphens", () => {
    for (const tool of [...browserTools, ...cliTools]) {
      expect(tool.name).not.toContain("-");
    }
  });

  it("bodyFromArgs strips device from browser tools", () => {
    const navTool = browserTools.find((t) => t.name === "mollotov_navigate")!;
    const body = navTool.bodyFromArgs({ device: "iphone", url: "https://example.com" });
    expect(body).toEqual({ url: "https://example.com" });
    expect(body).not.toHaveProperty("device");
  });

  it("bodyFromArgs strips filter params from CLI tools", () => {
    const groupNav = cliTools.find((t) => t.name === "mollotov_group_navigate")!;
    const body = groupNav.bodyFromArgs({ platform: "ios", include: "iPhone", exclude: "", url: "https://example.com" });
    expect(body).toEqual({ url: "https://example.com" });
    expect(body).not.toHaveProperty("platform");
    expect(body).not.toHaveProperty("include");
    expect(body).not.toHaveProperty("exclude");
  });
});
