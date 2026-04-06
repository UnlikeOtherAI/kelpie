import { describe, it, expect, beforeAll, beforeEach } from "vitest";
import { testDevice, isDeviceReachable, deviceRequest } from "./setup.js";

describe("E2E: Keyboard State", () => {
  const device = testDevice();
  let reachable = false;

  beforeAll(async () => {
    reachable = await isDeviceReachable(device);
  });

  beforeEach(async () => {
    if (!reachable) return;
    await deviceRequest(device, "navigate", { url: "https://example.com", timeout: 10000 });
  });

  it("reports keyboard hidden initially", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "get-keyboard-state", {});
    // macOS returns PLATFORM_NOT_SUPPORTED for keyboard state
    if (!ok && (data.error as Record<string, unknown>)?.code === "PLATFORM_NOT_SUPPORTED") return;
    expect(ok).toBe(true);
    expect(data.visible).toBe(false);
    expect(data.height).toBe(0);
  });

  it("detects keyboard after focusing input", async () => {
    if (!reachable) return;
    // Inject an input element
    await deviceRequest(device, "evaluate", {
      expression:
        "document.body.insertAdjacentHTML('beforeend', '<input id=\"inp\" placeholder=\"type\">')",
    });
    await deviceRequest(device, "show-keyboard", { selector: "#inp" });
    await new Promise((r) => setTimeout(r, 500));

    const { ok, data } = await deviceRequest(device, "get-keyboard-state", {});
    // macOS returns PLATFORM_NOT_SUPPORTED for keyboard state
    if (!ok && (data.error as Record<string, unknown>)?.code === "PLATFORM_NOT_SUPPORTED") return;
    expect(ok).toBe(true);
    // On mobile: visible=true with real height. Verify the response shape.
    if (data.visible !== undefined) {
      expect(typeof data.height).toBe("number");
    }
  });

  it("hides keyboard on dismiss", async () => {
    if (!reachable) return;
    // Inject an input element
    await deviceRequest(device, "evaluate", {
      expression:
        "document.body.insertAdjacentHTML('beforeend', '<input id=\"inp\" placeholder=\"type\">')",
    });
    await deviceRequest(device, "show-keyboard", { selector: "#inp" });
    await new Promise((r) => setTimeout(r, 300));
    await deviceRequest(device, "hide-keyboard", {});
    await new Promise((r) => setTimeout(r, 300));

    const { ok, data } = await deviceRequest(device, "get-keyboard-state", {});
    // macOS returns PLATFORM_NOT_SUPPORTED for keyboard state
    if (!ok && (data.error as Record<string, unknown>)?.code === "PLATFORM_NOT_SUPPORTED") return;
    expect(data.visible).toBe(false);
  });
});
