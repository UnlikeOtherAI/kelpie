import { describe, it, expect, beforeAll } from "vitest";
import { testDevice, isDeviceReachable, deviceRequest } from "./setup.js";

describe("E2E: AI Inference", () => {
  const device = testDevice();
  let reachable = false;

  beforeAll(async () => {
    reachable = await isDeviceReachable(device);
  });

  it("reports ai status", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "ai-status", {});
    expect(ok).toBe(true);
    expect(data).toHaveProperty("loaded");
    // backend may be absent when no model is loaded (e.g. macOS with no AI backend)
    expect(typeof data.loaded).toBe("boolean");
  });

  it("loads and queries ollama model if available", async () => {
    if (!reachable) return;
    const load = await deviceRequest(device, "ai-load", { model: "ollama:tinyllama" });
    if (!load.ok) return; // Ollama not configured, skip gracefully

    const status = await deviceRequest(device, "ai-status", {});
    expect(status.data.loaded).toBe(true);
    expect(status.data).toHaveProperty("backend");

    const infer = await deviceRequest(device, "ai-infer", {
      prompt: "Say hello in one word",
    });
    // Ollama may be configured but not running — inference can fail with
    // OLLAMA_DISCONNECTED. Only assert response shape when inference succeeds.
    if (!infer.ok) return;
    expect(infer.data).toHaveProperty("response");

    await deviceRequest(device, "ai-unload", {});
  });

  it("unload reverts to platform backend", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "ai-unload", {});
    expect(ok).toBe(true);
    expect(data).toHaveProperty("success", true);
  });
});
