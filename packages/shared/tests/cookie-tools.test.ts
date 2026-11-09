import { describe, expect, it } from "vitest";
import { z } from "zod";
import { BrowserMcpTools, BrowserToolUnsupportedPlatforms, MAX_SET_COOKIES, httpToMcp, sharedBrowserTools } from "../src/index.js";

const tool = (name: string) => {
  const found = sharedBrowserTools.find((candidate) => candidate.name === name);
  if (!found) throw new Error(`missing ${name}`);
  return { ...found, parse: (args: unknown) => z.strictObject(found.schema).safeParse(args) };
};

const cookie = {
  name: "sid",
  value: "v",
  domain: ".example.com",
  path: "/",
  expires: null,
  httpOnly: true,
  secure: true,
  sameSite: "Unspecified",
};

const kebab = (method: string) => method.replace(/([a-z])([A-Z])/g, "$1-$2").toLowerCase();

describe("cookie tools", () => {
  const names = ["kelpie_get_cookies", "kelpie_set_cookies", "kelpie_copy_cookies", "kelpie_get_cookie_sync_status"];

  it("map each method to its HTTP endpoint and back to the same tool on every platform", () => {
    const endpoints = {
      kelpie_get_cookies: "get-cookies",
      kelpie_set_cookies: "set-cookies",
      kelpie_copy_cookies: "copy-cookies",
      kelpie_get_cookie_sync_status: "get-cookie-sync-status",
    } as const;
    for (const name of names) {
      const definition = tool(name);
      const endpoint = endpoints[name as keyof typeof endpoints];
      expect(BrowserMcpTools).toContain(name);
      expect(kebab(definition.method)).toBe(endpoint);
      expect(name.slice("kelpie_".length).replaceAll("_", "-")).toBe(endpoint);
      expect(httpToMcp[endpoint]).toBe(name);
      expect(definition.platforms).toBeUndefined();
      expect(name in BrowserToolUnsupportedPlatforms).toBe(false);
    }
  });

  it("get-cookies accepts all, domain and a partition target, and checks the partition", () => {
    const get = tool("kelpie_get_cookies");
    expect(get.parse({ device: "d", all: true, domain: "example.com", partition: "work" }).success).toBe(true);
    expect(get.parse({ device: "d", all: true, tabId: "t1" }).success).toBe(true);
    expect(get.parse({ device: "d", partition: "default" }).success).toBe(false);
  });

  it("set-cookies takes full cookie records, at most 500, with the four sameSite values", () => {
    const set = tool("kelpie_set_cookies");
    expect(MAX_SET_COOKIES).toBe(500);
    expect(set.parse({ device: "d", cookies: [cookie], partition: "work" }).success).toBe(true);
    for (const sameSite of ["Strict", "Lax", "None", "Unspecified"]) {
      expect(set.parse({ device: "d", cookies: [{ ...cookie, sameSite }] }).success).toBe(true);
    }
    expect(set.parse({ device: "d", cookies: [{ ...cookie, sameSite: "lax" }] }).success).toBe(false);
    expect(set.parse({ device: "d", cookies: [{ ...cookie, path: undefined }] }).success).toBe(false);
    expect(set.parse({ device: "d", cookies: Array.from({ length: MAX_SET_COOKIES }, () => cookie) }).success).toBe(true);
    expect(set.parse({ device: "d", cookies: Array.from({ length: MAX_SET_COOKIES + 1 }, () => cookie) }).success).toBe(false);
  });

  it("copy-cookies needs both stores, where {} is the default store", () => {
    const copy = tool("kelpie_copy_cookies");
    expect(copy.parse({ device: "d", from: {}, to: { tabId: "t2" }, domain: "example.com" }).success).toBe(true);
    expect(copy.parse({ device: "d", from: { partition: "work" }, to: {} }).success).toBe(true);
    expect(copy.parse({ device: "d", to: { tabId: "t2" } }).success).toBe(false);
    expect(copy.parse({ device: "d", from: { partition: "ephemeral-x" }, to: {} }).success).toBe(false);
    expect(copy.bodyFromArgs({ device: "d", from: {}, to: { tabId: "t2" } })).toEqual({ from: {}, to: { tabId: "t2" } });
  });

  it("get-cookie-sync-status takes no arguments beyond the device", () => {
    const status = tool("kelpie_get_cookie_sync_status");
    expect(status.parse({ device: "d" }).success).toBe(true);
    expect(status.bodyFromArgs({ device: "d" })).toEqual({});
  });

  it("tells an agent how to move synced cookies into an isolated tab", () => {
    const copy = tool("kelpie_copy_cookies").description;
    expect(copy).toContain("default store");
    expect(copy).toContain("kelpie_new_tab");
    expect(copy).toContain("to:{tabId");
    expect(tool("kelpie_get_cookies").description).toContain("all:true");
  });
});
