import { describe, expect, it } from "vitest";
import { z } from "zod";
import { BrowserMcpTools, BrowserToolUnsupportedPlatforms, httpToMcp, sharedBrowserTools } from "../src/index.js";

const tool = (name: string) => {
  const found = sharedBrowserTools.find((candidate) => candidate.name === name);
  if (!found) throw new Error(`missing ${name}`);
  return { ...found, parse: (args: unknown) => z.strictObject(found.schema).safeParse(args) };
};

const kebab = (method: string) => method.replace(/([a-z])([A-Z])/g, "$1-$2").toLowerCase();

describe("download tools", () => {
  const endpoints = { kelpie_download: "download", kelpie_get_downloads: "get-downloads" } as const;

  it("map to their native endpoints and are advertised on macOS only", () => {
    for (const [name, endpoint] of Object.entries(endpoints)) {
      const definition = tool(name);
      expect(BrowserMcpTools).toContain(name);
      expect(kebab(definition.method)).toBe(endpoint);
      expect(name.slice("kelpie_".length).replaceAll("_", "-")).toBe(endpoint);
      expect(httpToMcp[endpoint]).toBe(name);
      expect(definition.platforms).toEqual(["macos"]);
      expect(BrowserToolUnsupportedPlatforms[name as keyof typeof endpoints]).toEqual(["ios", "android", "linux", "windows"]);
    }
  });

  it("require a URL to download and forward the tab that owns the session", () => {
    const download = tool("kelpie_download");
    expect(download.parse({ device: "mac" }).success).toBe(false);
    const parsed = download.parse({ device: "mac", url: "https://example.com/a.zip", tabId: "tab-1" });
    expect(parsed.success).toBe(true);
    expect(download.bodyFromArgs(parsed.data!)).toMatchObject({ url: "https://example.com/a.zip", tabId: "tab-1" });
    expect(download.parse({ device: "mac", url: "https://example.com/a.zip", path: "/etc" }).success).toBe(false);
  });

  it("list every download or one by id", () => {
    const list = tool("kelpie_get_downloads");
    expect(list.parse({ device: "mac" }).success).toBe(true);
    expect(list.parse({ device: "mac", id: "d1" }).success).toBe(true);
  });
});
