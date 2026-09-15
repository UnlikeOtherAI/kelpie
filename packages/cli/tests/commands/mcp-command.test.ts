import { describe, expect, it } from "vitest";
import { rejectsWindowsLocalHttpProxy } from "../../src/commands/mcp.js";

describe("local MCP transport security", () => {
  it("does not proxy a Windows launch capability through the CLI HTTP server", () => {
    expect(rejectsWindowsLocalHttpProxy(true, "windows")).toBe(true);
    expect(rejectsWindowsLocalHttpProxy(false, "windows")).toBe(false);
    expect(rejectsWindowsLocalHttpProxy(true, "macos")).toBe(false);
  });
});
