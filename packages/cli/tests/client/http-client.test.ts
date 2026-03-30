import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { sendCommand } from "../../src/client/http-client.js";
import type { DiscoveredDevice } from "../../src/types.js";

const device: DiscoveredDevice = {
  id: "test-uuid",
  name: "Test Device",
  ip: "192.168.1.42",
  port: 8420,
  platform: "ios",
  model: "iPhone 15",
  width: 390,
  height: 844,
  version: "1.0.0",
  lastSeen: Date.now(),
};

describe("HTTP client", () => {
  const originalFetch = globalThis.fetch;

  afterEach(() => {
    globalThis.fetch = originalFetch;
  });

  it("builds correct URL with kebab-case method", async () => {
    let capturedUrl = "";
    globalThis.fetch = vi.fn(async (url: string | URL | Request) => {
      capturedUrl = url as string;
      return new Response(JSON.stringify({ success: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }) as typeof fetch;

    await sendCommand(device, "getDeviceInfo");
    expect(capturedUrl).toBe("http://192.168.1.42:8420/v1/get-device-info");
  });

  it("sends JSON body", async () => {
    let capturedBody = "";
    globalThis.fetch = vi.fn(async (_url: string | URL | Request, init?: RequestInit) => {
      capturedBody = init?.body as string;
      return new Response(JSON.stringify({ success: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }) as typeof fetch;

    await sendCommand(device, "navigate", { url: "https://example.com" });
    expect(JSON.parse(capturedBody)).toEqual({ url: "https://example.com" });
  });

  it("returns parsed JSON response", async () => {
    const mockData = { success: true, url: "https://example.com", title: "Example" };
    globalThis.fetch = vi.fn(async () =>
      new Response(JSON.stringify(mockData), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    ) as typeof fetch;

    const result = await sendCommand(device, "navigate", { url: "https://example.com" });
    expect(result.ok).toBe(true);
    expect(result.status).toBe(200);
    expect(result.data).toEqual(mockData);
  });

  it("handles network errors", async () => {
    globalThis.fetch = vi.fn(async () => {
      throw new Error("Connection refused");
    }) as typeof fetch;

    const result = await sendCommand(device, "navigate");
    expect(result.ok).toBe(false);
    expect(result.status).toBe(0);
    expect((result.data as Record<string, unknown>)).toHaveProperty("success", false);
  });

  it("converts camelCase to kebab-case", async () => {
    let capturedUrl = "";
    globalThis.fetch = vi.fn(async (url: string | URL | Request) => {
      capturedUrl = url as string;
      return new Response(JSON.stringify({ success: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }) as typeof fetch;

    await sendCommand(device, "getConsoleMessages");
    expect(capturedUrl).toContain("/v1/get-console-messages");

    await sendCommand(device, "querySelectorAll");
    expect(capturedUrl).toContain("/v1/query-selector-all");
  });
});
