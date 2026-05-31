import { describe, it, expect, vi, afterEach } from "vitest";
import { addDevice, clearDevices } from "../../src/discovery/registry.js";
import type { DiscoveredDevice } from "../../src/types.js";

const device: DiscoveredDevice = {
  id: "test-uuid",
  name: "Test iPhone",
  ip: "192.168.1.42",
  port: 8420,
  platform: "ios",
  model: "iPhone 15 Pro",
  width: 390,
  height: 844,
  version: "1.0.0",
  lastSeen: Date.now(),
};

function mockFetch(response: unknown, status = 200) {
  globalThis.fetch = vi.fn(async () =>
    new Response(JSON.stringify(response), {
      status,
      headers: { "Content-Type": "application/json" },
    }),
  ) as typeof fetch;
}

function capturedUrl(): string {
  return (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0]?.[0] as string;
}

function capturedBody(): Record<string, unknown> | undefined {
  const init = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0]?.[1] as RequestInit | undefined;
  return init?.body ? JSON.parse(init.body as string) : undefined;
}

// We test the helpers + http-client integration since commands just wire Commander to deviceCommand
import { sendCommand } from "../../src/client/http-client.js";
import { withGlobalTabId } from "../../src/commands/helpers.js";

describe("command API method mapping", () => {
  const originalFetch = globalThis.fetch;

  afterEach(() => {
    globalThis.fetch = originalFetch;
    clearDevices();
  });

  it("navigate sends correct URL and body", async () => {
    mockFetch({ success: true, url: "https://example.com", title: "Example", loadTime: 100 });
    addDevice(device);
    await sendCommand(device, "navigate", { url: "https://example.com" });
    expect(capturedUrl()).toBe("http://192.168.1.42:8420/v1/navigate");
    expect(capturedBody()).toEqual({ url: "https://example.com" });
  });

  it("back sends to /v1/back", async () => {
    mockFetch({ success: true });
    await sendCommand(device, "back");
    expect(capturedUrl()).toContain("/v1/back");
  });

  it("screenshot sends format and fullPage", async () => {
    mockFetch({ success: true, image: "abc", width: 390, height: 844, format: "png" });
    await sendCommand(device, "screenshot", { fullPage: true, format: "png" });
    expect(capturedBody()).toEqual({ fullPage: true, format: "png" });
  });

  it("click sends selector", async () => {
    mockFetch({ success: true, element: { tag: "button", text: "Submit" } });
    await sendCommand(device, "click", { selector: "#submit" });
    expect(capturedUrl()).toContain("/v1/click");
    expect(capturedBody()).toEqual({ selector: "#submit" });
  });

  it("playScript sends to /v1/play-script", async () => {
    mockFetch({ success: true, actionsExecuted: 1, totalDurationMs: 100, errors: [], screenshots: [] });
    await sendCommand(device, "playScript", { actions: [{ action: "wait", ms: 100 }] });
    expect(capturedUrl()).toContain("/v1/play-script");
    expect(capturedBody()).toEqual({ actions: [{ action: "wait", ms: 100 }] });
  });

  it("playScript preserves script action shorthands like commentary", async () => {
    mockFetch({ success: true, actionsExecuted: 2, totalDurationMs: 100, errors: [], screenshots: [] });
    await sendCommand(device, "playScript", {
      actions: [
        { action: "commentary", text: "Welcome", durationMs: 0 },
        { action: "hide-commentary" },
      ],
    });
    expect(capturedUrl()).toContain("/v1/play-script");
    expect(capturedBody()).toEqual({
      actions: [
        { action: "commentary", text: "Welcome", durationMs: 0 },
        { action: "hide-commentary" },
      ],
    });
  });

  it("showCommentary converts to show-commentary", async () => {
    mockFetch({ success: true, text: "hello" });
    await sendCommand(device, "showCommentary", { text: "hello", durationMs: 0 });
    expect(capturedUrl()).toContain("/v1/show-commentary");
    expect(capturedBody()).toEqual({ text: "hello", durationMs: 0 });
  });

  it("getScriptStatus converts to get-script-status", async () => {
    mockFetch({ playing: false });
    await sendCommand(device, "getScriptStatus");
    expect(capturedUrl()).toContain("/v1/get-script-status");
  });

  it("fill sends selector and value", async () => {
    mockFetch({ success: true });
    await sendCommand(device, "fill", { selector: "#email", value: "test@test.com" });
    expect(capturedBody()).toEqual({ selector: "#email", value: "test@test.com" });
  });

  it("scroll2 sends selector and position", async () => {
    mockFetch({ success: true });
    await sendCommand(device, "scroll2", { selector: "#footer", position: "center", maxScrolls: 10 });
    expect(capturedUrl()).toContain("/v1/scroll2");
    expect(capturedBody()).toEqual({ selector: "#footer", position: "center", maxScrolls: 10 });
  });

  it("getConsoleMessages converts to get-console-messages", async () => {
    mockFetch({ success: true, messages: [], count: 0 });
    await sendCommand(device, "getConsoleMessages", { level: "error", limit: 50 });
    expect(capturedUrl()).toContain("/v1/get-console-messages");
    expect(capturedBody()).toEqual({ level: "error", limit: 50 });
  });

  it("getAccessibilityTree converts correctly", async () => {
    mockFetch({ success: true, tree: {}, nodeCount: 0 });
    await sendCommand(device, "getAccessibilityTree", { interactableOnly: true });
    expect(capturedUrl()).toContain("/v1/get-accessibility-tree");
  });

  it("findButton sends text", async () => {
    mockFetch({ found: true, element: { tag: "button", text: "Submit" } });
    await sendCommand(device, "findButton", { text: "Submit" });
    expect(capturedUrl()).toContain("/v1/find-button");
    expect(capturedBody()).toEqual({ text: "Submit" });
  });

  it("setGeolocation sends coordinates", async () => {
    mockFetch({ success: true });
    await sendCommand(device, "setGeolocation", { latitude: 37.77, longitude: -122.42, accuracy: 10 });
    expect(capturedUrl()).toContain("/v1/set-geolocation");
    expect(capturedBody()).toEqual({ latitude: 37.77, longitude: -122.42, accuracy: 10 });
  });

  it("toast sends the message payload", async () => {
    mockFetch({ success: true, message: "hello" });
    await sendCommand(device, "toast", { message: "hello" });
    expect(capturedUrl()).toContain("/v1/toast");
    expect(capturedBody()).toEqual({ message: "hello" });
  });

  it("debugScreens converts to debug-screens", async () => {
    mockFetch({ success: true, screens: [] });
    await sendCommand(device, "debugScreens");
    expect(capturedUrl()).toContain("/v1/debug-screens");
  });

  it("safariAuth converts to safari-auth", async () => {
    mockFetch({ success: true, started: true });
    await sendCommand(device, "safariAuth", { url: "https://example.com/login" });
    expect(capturedUrl()).toContain("/v1/safari-auth");
    expect(capturedBody()).toEqual({ url: "https://example.com/login" });
  });

  it("watchMutations sends options", async () => {
    mockFetch({ success: true, watchId: "mut_001" });
    await sendCommand(device, "watchMutations", { selector: "main", attributes: true, childList: true, subtree: true });
    expect(capturedUrl()).toContain("/v1/watch-mutations");
  });

  it("queryShadowDOM sends host and shadow selectors", async () => {
    mockFetch({ success: true, found: true });
    await sendCommand(device, "queryShadowDOM", { hostSelector: "my-component", shadowSelector: ".btn", pierce: true });
    expect(capturedUrl()).toContain("/v1/query-shadow-dom");
    expect(capturedBody()?.hostSelector).toBe("my-component");
  });

  it("withGlobalTabId injects tabId when missing", () => {
    expect(withGlobalTabId({
      device: "dictator",
      format: "json",
      timeout: 10000,
      port: 8420,
      tabId: "tab-123",
    }, { selector: "#submit" })).toEqual({ selector: "#submit", tabId: "tab-123" });
  });

  it("withGlobalTabId does not override an explicit tabId", () => {
    expect(withGlobalTabId({
      device: "dictator",
      format: "json",
      timeout: 10000,
      port: 8420,
      tabId: "tab-123",
    }, { tabId: "tab-456", selector: "#submit" })).toEqual({ tabId: "tab-456", selector: "#submit" });
  });
});
