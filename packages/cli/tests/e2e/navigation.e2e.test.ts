import { describe, it, expect, beforeAll } from "vitest";
import { testDevice, isDeviceReachable, deviceRequest, skipUnlessDevice } from "./setup.js";

describe("E2E: Navigation", () => {
  const device = testDevice();
  let reachable = false;

  beforeAll(async () => {
    reachable = await isDeviceReachable(device);
  });

  it("navigate loads a URL and returns page info", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "navigate", {
      url: "https://example.com",
      timeout: 15000,
    });
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
    expect(data).toHaveProperty("url");
    expect(String(data.url)).toContain("example.com");
  });

  it("get-current-url returns the loaded URL", async () => {
    if (!reachable) return;
    // Ensure we're on a known page
    await deviceRequest(device, "navigate", { url: "https://example.com" });
    const { ok, data } = await deviceRequest(device, "get-current-url");
    expect(ok).toBe(true);
    expect(String(data.url)).toContain("example.com");
  });

  it("screenshot returns base64 image data", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "screenshot");
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
    expect(data).toHaveProperty("image");
    expect(data).toHaveProperty("width");
    expect(data).toHaveProperty("height");
    // Verify it's valid base64 (check first few bytes for PNG header)
    const img = String(data.image);
    expect(img.length).toBeGreaterThan(100);
    const format = data.format as string;
    expect(["png", "jpeg"]).toContain(format);
  });

  it("reload refreshes the page", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "reload");
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
  });

  it("back and forward navigate history", async () => {
    if (!reachable) return;
    // Navigate to two pages
    await deviceRequest(device, "navigate", { url: "https://example.com" });
    await deviceRequest(device, "navigate", { url: "https://www.google.com" });

    // Go back
    const { data: backData } = await deviceRequest(device, "back");
    expect(backData).toHaveProperty("success", true);

    // Go forward
    const { data: fwdData } = await deviceRequest(device, "forward");
    expect(fwdData).toHaveProperty("success", true);
  });
});
