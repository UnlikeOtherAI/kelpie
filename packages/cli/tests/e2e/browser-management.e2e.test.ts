import { describe, it, expect, beforeAll, beforeEach } from "vitest";
import { testDevice, isDeviceReachable, deviceRequest } from "./setup.js";

describe("E2E: Browser Management", () => {
  const device = testDevice();
  let reachable = false;

  beforeAll(async () => {
    reachable = await isDeviceReachable(device);
  });

  beforeEach(async () => {
    if (!reachable) return;
    await deviceRequest(device, "navigate", { url: "https://example.com", timeout: 10000 });
  });

  // Cookies
  it("set-cookie and get-cookies round trip", async () => {
    if (!reachable) return;
    await deviceRequest(device, "set-cookie", { name: "test_cookie", value: "e2e_value" });
    const { ok, data } = await deviceRequest(device, "get-cookies");
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
    expect(data).toHaveProperty("cookies");
  });

  it("delete-cookies clears cookies", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "delete-cookies", { deleteAll: true });
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
  });

  // Storage
  it("set-storage and get-storage round trip", async () => {
    if (!reachable) return;
    await deviceRequest(device, "set-storage", { key: "test_key", value: "test_val" });
    const { ok, data } = await deviceRequest(device, "get-storage", { key: "test_key" });
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
  });

  it("clear-storage removes stored data", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "clear-storage", { type: "both" });
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
  });

  // Console & DevTools
  it("get-console-messages returns message list", async () => {
    if (!reachable) return;
    // Trigger a console.log
    await deviceRequest(device, "evaluate", { expression: "console.log('e2e test')" });
    const { ok, data } = await deviceRequest(device, "get-console-messages");
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
    expect(data).toHaveProperty("messages");
    expect(data).toHaveProperty("count");
  });

  it("get-js-errors returns error list", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "get-js-errors");
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
    expect(data).toHaveProperty("errors");
  });

  it("clear-console resets message buffer", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "clear-console");
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
    expect(data).toHaveProperty("cleared");
  });

  // Network
  it("get-network-log returns resource entries", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "get-network-log");
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
    expect(data).toHaveProperty("entries");
    expect(data).toHaveProperty("count");
  });

  it("get-resource-timeline returns timing data", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "get-resource-timeline");
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
    expect(data).toHaveProperty("pageUrl");
    expect(data).toHaveProperty("resources");
  });

  // Mutations
  it("watch-mutations starts observer", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "watch-mutations", { selector: "body" });
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
    expect(data).toHaveProperty("watchId");
    expect(data).toHaveProperty("watching", true);

    // Cleanup
    const watchId = data.watchId as string;
    await deviceRequest(device, "stop-watching", { watchId });
  });

  it("get-mutations retrieves buffered mutations", async () => {
    if (!reachable) return;
    // Start watching
    const { data: watchData } = await deviceRequest(device, "watch-mutations", { selector: "body" });
    const watchId = watchData.watchId as string;

    // Trigger a DOM change
    await deviceRequest(device, "evaluate", {
      expression: "document.body.appendChild(document.createElement('div'))",
    });

    // Wait a moment for mutation to be captured
    await new Promise((r) => setTimeout(r, 200));

    const { ok, data } = await deviceRequest(device, "get-mutations", { watchId, clear: true });
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
    expect(data).toHaveProperty("mutations");

    await deviceRequest(device, "stop-watching", { watchId });
  });

  // Iframes
  it("get-iframes lists iframes on page", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "get-iframes");
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
    expect(data).toHaveProperty("iframes");
    expect(data).toHaveProperty("count");
  });

  // Tabs
  it("get-tabs returns current tab list", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "get-tabs");
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
    expect(data).toHaveProperty("tabs");
    expect(data).toHaveProperty("count");
    expect(typeof data.count).toBe("number");
  });

  // Clipboard
  it("set-clipboard and get-clipboard round trip", async () => {
    if (!reachable) return;
    await deviceRequest(device, "set-clipboard", { text: "e2e clipboard test" });
    const { ok, data } = await deviceRequest(device, "get-clipboard");
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
    expect(data).toHaveProperty("text");
  });
});
