import { describe, it, expect } from "vitest";
import {
  DEFAULT_PORT,
  MDNS_SERVICE_TYPE,
  API_VERSION_PREFIX,
  MCP_TOOL_PREFIX,
  ErrorCode,
  ErrorHttpStatus,
  BrowserMcpTools,
  BrowserToolUnsupportedPlatforms,
  CliMcpTools,
  httpToMcp,
} from "../src/index.js";

describe("constants", () => {
  it("has correct default port", () => {
    expect(DEFAULT_PORT).toBe(8420);
  });

  it("has correct mDNS service type", () => {
    expect(MDNS_SERVICE_TYPE).toBe("_kelpie._tcp");
  });

  it("has correct API version prefix", () => {
    expect(API_VERSION_PREFIX).toBe("/v1/");
  });

  it("has correct MCP tool prefix", () => {
    expect(MCP_TOOL_PREFIX).toBe("kelpie_");
  });
});

describe("error codes", () => {
  it("has all documented error codes", () => {
    const expected = [
      "ELEMENT_NOT_FOUND",
      "ELEMENT_NOT_VISIBLE",
      "TIMEOUT",
      "NAVIGATION_ERROR",
      "INVALID_SELECTOR",
      "INVALID_PARAMS",
      "WEBVIEW_ERROR",
      "IFRAME_ACCESS_DENIED",
      "WATCH_NOT_FOUND",
      "ANNOTATION_EXPIRED",
      "RECORDING_IN_PROGRESS",
      "PLATFORM_NOT_SUPPORTED",
      "PERMISSION_REQUIRED",
      "SHADOW_ROOT_CLOSED",
    ];
    expect(Object.keys(ErrorCode)).toEqual(expected);
  });

  it("has HTTP status mapping for every error code", () => {
    for (const code of Object.values(ErrorCode)) {
      expect(ErrorHttpStatus[code]).toBeGreaterThanOrEqual(400);
    }
  });
});

describe("MCP tools", () => {
  it("all browser tools use kelpie_ prefix", () => {
    for (const tool of BrowserMcpTools) {
      expect(tool).toMatch(/^kelpie_/);
    }
  });

  it("all CLI tools use kelpie_ prefix", () => {
    for (const tool of CliMcpTools) {
      expect(tool).toMatch(/^kelpie_/);
    }
  });

  it("has correct count of browser tools", () => {
    expect(BrowserMcpTools.length).toBe(112);
  });

  it("has correct count of CLI tools", () => {
    expect(CliMcpTools.length).toBe(23);
  });

  it("httpToMcp maps all browser endpoints", () => {
    const mappedTools = Object.values(httpToMcp);
    expect(mappedTools.length).toBe(BrowserMcpTools.length);
    for (const tool of BrowserMcpTools) {
      expect(mappedTools).toContain(tool);
    }
  });

  it("tracks linux and windows unsupported browser tools", () => {
    expect(BrowserToolUnsupportedPlatforms.kelpie_ai_status).toEqual(["linux", "windows"]);
    expect(BrowserToolUnsupportedPlatforms.kelpie_ai_load).toEqual(["linux", "windows"]);
    expect(BrowserToolUnsupportedPlatforms.kelpie_ai_unload).toEqual(["linux", "windows"]);
    expect(BrowserToolUnsupportedPlatforms.kelpie_ai_ask).toEqual(["linux", "windows"]);
    expect(BrowserToolUnsupportedPlatforms.kelpie_ai_record).toEqual(["linux", "windows"]);
    expect(BrowserToolUnsupportedPlatforms.kelpie_show_keyboard).toEqual(["linux", "windows"]);
    expect(BrowserToolUnsupportedPlatforms.kelpie_hide_keyboard).toEqual(["linux", "windows"]);
    expect(BrowserToolUnsupportedPlatforms.kelpie_get_viewport_presets).toEqual(["linux", "windows"]);
    expect(BrowserToolUnsupportedPlatforms.kelpie_set_viewport_preset).toEqual(["linux", "windows"]);
    expect(BrowserToolUnsupportedPlatforms.kelpie_set_orientation).toEqual(["linux", "windows"]);
    expect(BrowserToolUnsupportedPlatforms.kelpie_safari_auth).toEqual(["linux", "windows"]);
  });
});
