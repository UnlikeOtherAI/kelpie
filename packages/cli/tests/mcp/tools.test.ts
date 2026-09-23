import { describe, it, expect } from "vitest";
import { browserTools, cliTools } from "../../src/mcp/tools.js";
import { BrowserMcpTools, CliMcpTools } from "../../../shared/src/index.js";

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

  it("group tool platform filters accept linux and windows", () => {
    const groupNav = cliTools.find((t) => t.name === "kelpie_group_navigate")!;
    expect(groupNav.schema.platform.safeParse("linux").success).toBe(true);
    expect(groupNav.schema.platform.safeParse("windows").success).toBe(true);
    expect(groupNav.schema.platform.safeParse("unknown").success).toBe(false);
  });

  it("group tools do NOT have device property", () => {
    const groupTools = cliTools.filter((t) => t.kind === "group" || t.kind === "smartQuery");
    for (const tool of groupTools) {
      expect(tool.schema).not.toHaveProperty("device");
    }
  });

  it("kelpie_pair targets a single device", () => {
    const pairTool = cliTools.find((t) => t.name === "kelpie_pair");
    expect(pairTool).toBeDefined();
    expect(pairTool!.schema).toHaveProperty("device");
  });

  it("all tool names use kelpie_ prefix", () => {
    for (const tool of [...browserTools, ...cliTools]) {
      expect(tool.name).toMatch(/^kelpie_/);
    }
  });

  it("all tool names use underscores not hyphens", () => {
    for (const tool of [...browserTools, ...cliTools]) {
      expect(tool.name).not.toContain("-");
    }
  });

  it("bodyFromArgs strips device from browser tools", () => {
    const navTool = browserTools.find((t) => t.name === "kelpie_navigate")!;
    const body = navTool.bodyFromArgs({ device: "iphone", url: "https://example.com" });
    expect(body).toEqual({ url: "https://example.com" });
    expect(body).not.toHaveProperty("device");
  });

  it("coordinate diagnostics accepts point and action schemas", () => {
    const tool = browserTools.find((t) => t.name === "kelpie_coordinate_diagnostics")!;
    const args = {
      device: "iphone",
      points: [{ label: "pay", x: 120, y: 240, expectedSelector: "#pay" }],
      actions: [
        { type: "tap", x: 120, y: 240, expectedSelector: "#pay" },
        { type: "swipe", from: { x: 200, y: 600 }, to: { x: 200, y: 300 }, steps: 12 },
        { type: "scroll", deltaX: 0, deltaY: 300 },
      ],
      captureScreenshot: true,
      screenshotResolution: "viewport",
    };
    expect(tool.schema.points.safeParse(args.points).success).toBe(true);
    expect(tool.schema.actions.safeParse(args.actions).success).toBe(true);
    expect(tool.bodyFromArgs(args)).not.toHaveProperty("device");
  });

  it("bodyFromArgs strips filter params from CLI tools", () => {
    const groupNav = cliTools.find((t) => t.name === "kelpie_group_navigate")!;
    const body = groupNav.bodyFromArgs({ platform: "ios", include: "iPhone", exclude: "", url: "https://example.com" });
    expect(body).toEqual({ url: "https://example.com" });
    expect(body).not.toHaveProperty("platform");
    expect(body).not.toHaveProperty("include");
    expect(body).not.toHaveProperty("exclude");
  });
});

describe("partition tools", () => {
  const byName = (name: string) => browserTools.find((t) => t.name === name);

  it("exposes get-partitions and delete-partition on the platforms that isolate storage", () => {
    expect(byName("kelpie_get_partitions")?.method).toBe("getPartitions");
    expect(byName("kelpie_delete_partition")?.method).toBe("deletePartition");
    expect(byName("kelpie_get_partitions")?.platforms).toEqual(["macos", "windows"]);
    expect(byName("kelpie_delete_partition")?.platforms).toEqual(["macos", "windows"]);
  });

  it("validates the delete-partition id with the shared partition rules", () => {
    const schema = byName("kelpie_delete_partition")?.schema.id;
    expect(schema?.safeParse("sam.eng-lead").success).toBe(true);
    expect(schema?.safeParse("default").success).toBe(false);
    expect(schema?.safeParse("ephemeral-sam").success).toBe(false);
    expect(schema?.safeParse("has space").success).toBe(false);
    expect(schema?.safeParse("a".repeat(129)).success).toBe(false);
  });

  it("applies the same partition rules to new-tab, and keeps every new field optional", () => {
    const schema = byName("kelpie_new_tab")?.schema;
    expect(schema?.partition?.safeParse("sam").success).toBe(true);
    expect(schema?.partition?.safeParse("..").success).toBe(false);
    // Optional, so an existing caller that sends only a url still validates.
    expect(schema?.partition?.safeParse(undefined).success).toBe(true);
    expect(schema?.name?.safeParse(undefined).success).toBe(true);
    expect(schema?.persistent?.safeParse(undefined).success).toBe(true);
    expect(schema?.name?.safeParse("x".repeat(201)).success).toBe(false);
    expect(schema?.persistent?.safeParse(false).success).toBe(true);
  });
});

describe("tool timeouts", () => {
  it("bounds every timeout argument to 1-30000 whole milliseconds", () => {
    for (const tool of browserTools.filter((t) => "timeout" in t.schema)) {
      expect(tool.schema.timeout?.safeParse(30_000).success).toBe(true);
      expect(tool.schema.timeout?.safeParse(30_001).success).toBe(false);
      expect(tool.schema.timeout?.safeParse(0).success).toBe(false);
      expect(tool.schema.timeout?.safeParse(1.5).success).toBe(false);
      expect(tool.schema.timeout?.safeParse(undefined).success).toBe(true);
    }
  });
});
