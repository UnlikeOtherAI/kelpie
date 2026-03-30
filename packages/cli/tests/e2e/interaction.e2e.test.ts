import { describe, it, expect, beforeAll, beforeEach } from "vitest";
import { testDevice, isDeviceReachable, deviceRequest } from "./setup.js";

describe("E2E: Interaction & DOM", () => {
  const device = testDevice();
  let reachable = false;

  beforeAll(async () => {
    reachable = await isDeviceReachable(device);
  });

  beforeEach(async () => {
    if (!reachable) return;
    // Navigate to example.com as a baseline page
    await deviceRequest(device, "navigate", { url: "https://example.com", timeout: 10000 });
  });

  it("get-dom returns HTML content", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "get-dom", { selector: "body" });
    expect(ok).toBe(true);
    expect(data).toHaveProperty("html");
    expect(String(data.html).length).toBeGreaterThan(0);
  });

  it("query-selector finds an element", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "query-selector", { selector: "h1" });
    expect(ok).toBe(true);
    expect(data).toHaveProperty("found", true);
    expect(data).toHaveProperty("element");
    const el = data.element as Record<string, unknown>;
    expect(el).toHaveProperty("tag", "h1");
    expect(el).toHaveProperty("text");
  });

  it("query-selector-all returns multiple elements", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "query-selector-all", { selector: "p" });
    expect(ok).toBe(true);
    expect(data).toHaveProperty("elements");
    expect(data).toHaveProperty("total");
    expect(typeof data.total).toBe("number");
  });

  it("get-element-text extracts text content", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "get-element-text", { selector: "h1" });
    expect(ok).toBe(true);
    expect(data).toHaveProperty("text");
    expect(String(data.text)).toContain("Example Domain");
  });

  it("get-attributes returns element attributes", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "get-attributes", { selector: "a" });
    expect(ok).toBe(true);
    expect(data).toHaveProperty("attributes");
    const attrs = data.attributes as Record<string, string>;
    expect(attrs).toHaveProperty("href");
  });

  it("click dispatches click on element", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "click", { selector: "a" });
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
  });

  it("evaluate runs arbitrary JavaScript", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "evaluate", {
      expression: "1 + 2",
    });
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
    expect(data).toHaveProperty("result");
  });

  it("scroll changes page scroll position", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "scroll", { deltaX: 0, deltaY: 100 });
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
  });

  it("scroll-to-top scrolls to page top", async () => {
    if (!reachable) return;
    // Scroll down first
    await deviceRequest(device, "scroll", { deltaX: 0, deltaY: 500 });
    const { ok, data } = await deviceRequest(device, "scroll-to-top");
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
  });

  it("wait-for-element finds existing element", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "wait-for-element", {
      selector: "h1",
      timeout: 5000,
      state: "visible",
    });
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
    expect(data).toHaveProperty("element");
    expect(data).toHaveProperty("waitTime");
  });

  it("wait-for-element times out for missing element", async () => {
    if (!reachable) return;
    const { data } = await deviceRequest(device, "wait-for-element", {
      selector: "#nonexistent-element-xyz",
      timeout: 1000,
    });
    expect(data).toHaveProperty("success", false);
    expect(data).toHaveProperty("error");
  });
});
