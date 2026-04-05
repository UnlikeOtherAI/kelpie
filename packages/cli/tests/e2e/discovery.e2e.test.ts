import { describe, it, expect, beforeAll } from "vitest";
import { testDevice, isDeviceReachable, deviceRequest } from "./setup.js";

describe("E2E: Discovery & Health", () => {
  const device = testDevice();
  let reachable = false;

  beforeAll(async () => {
    reachable = await isDeviceReachable(device);
  });

  it("health endpoint returns ok", async () => {
    if (!reachable) return;
    const res = await fetch(`http://${device.ip}:${device.port}/health`);
    expect(res.ok).toBe(true);
    const data = await res.json();
    expect(data).toHaveProperty("status", "ok");
  });

  it("get-device-info returns device metadata", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "get-device-info");
    expect(ok).toBe(true);
    expect(data).toHaveProperty("device");
    const dev = data.device as Record<string, unknown>;
    expect(dev).toHaveProperty("id");
    expect(dev).toHaveProperty("name");
    expect(dev).toHaveProperty("platform");
    expect(["ios", "android"]).toContain(dev.platform);
  });

  it("get-capabilities lists supported features", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "get-capabilities");
    expect(ok).toBe(true);
    expect(data).toHaveProperty("screenshot", true);
    expect(data).toHaveProperty("cookies", true);
    expect(data).toHaveProperty("storage", true);
  });

  it("get-viewport returns dimensions", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "get-viewport");
    expect(ok).toBe(true);
    expect(data).toHaveProperty("width");
    expect(data).toHaveProperty("height");
    expect(typeof data.width).toBe("number");
    expect(typeof data.height).toBe("number");
  });

  it("unknown method returns 404", async () => {
    if (!reachable) return;
    const { status, data } = await deviceRequest(device, "nonexistent-method");
    expect(status).toBe(404);
    expect(data).toHaveProperty("success", false);
  });
});
