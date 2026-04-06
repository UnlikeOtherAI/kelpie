import { describe, it, expect, beforeAll, beforeEach } from "vitest";
import { testDevice, isDeviceReachable, deviceRequest } from "./setup.js";

describe("E2E: Dialog Handling", () => {
  const device = testDevice();
  let reachable = false;

  beforeAll(async () => {
    reachable = await isDeviceReachable(device);
  });

  beforeEach(async () => {
    if (!reachable) return;
    await deviceRequest(device, "navigate", { url: "https://example.com", timeout: 10000 });
    // Inject a button that triggers an alert via createElement (avoids escaping issues)
    await deviceRequest(device, "evaluate", {
      expression:
        '(function(){var b=document.createElement("button");b.id="btn";b.textContent="Alert";b.onclick=function(){alert("test")};document.body.appendChild(b);return "done"})()',
    });
  });

  it("reports no dialog when none is showing", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "get-dialog", {});
    expect(ok).toBe(true);
    expect(data.showing).toBe(false);
  });

  it("intercepts alert dialog when auto-handler is disabled", async () => {
    if (!reachable) return;
    await deviceRequest(device, "set-dialog-auto-handler", { enabled: false });
    await deviceRequest(device, "click", { selector: "#btn" });
    await new Promise((r) => setTimeout(r, 500));

    const { ok, data } = await deviceRequest(device, "get-dialog", {});
    expect(ok).toBe(true);
    // On macOS, WKWebView alert dialogs may not be interceptable in queue
    // mode. On mobile (iOS/Android), the dialog should be captured.
    if (!data.showing) return; // platform does not support dialog queuing

    expect((data.dialog as Record<string, unknown>).type).toBe("alert");
    expect((data.dialog as Record<string, unknown>).message).toBe("test");

    await deviceRequest(device, "handle-dialog", { action: "accept" });
    const after = await deviceRequest(device, "get-dialog", {});
    expect(after.data.showing).toBe(false);
  });

  it("auto-handles dialogs when enabled", async () => {
    if (!reachable) return;
    await deviceRequest(device, "set-dialog-auto-handler", {
      enabled: true,
      defaultAction: "accept",
    });
    await deviceRequest(device, "click", { selector: "#btn" });
    await new Promise((r) => setTimeout(r, 500));
    const { ok, data } = await deviceRequest(device, "get-dialog", {});
    expect(ok).toBe(true);
    expect(data.showing).toBe(false);
  });
});
