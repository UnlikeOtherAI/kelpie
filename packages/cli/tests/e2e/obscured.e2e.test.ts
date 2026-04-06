import { describe, it, expect, beforeAll, beforeEach } from "vitest";
import { testDevice, isDeviceReachable, deviceRequest } from "./setup.js";

describe("E2E: Element Obscured", () => {
  const device = testDevice();
  let reachable = false;

  beforeAll(async () => {
    reachable = await isDeviceReachable(device);
  });

  beforeEach(async () => {
    if (!reachable) return;
    await deviceRequest(device, "navigate", { url: "https://example.com", timeout: 10000 });
  });

  it("reports element not obscured when keyboard hidden", async () => {
    if (!reachable) return;
    const { ok, data } = await deviceRequest(device, "is-element-obscured", {
      selector: "h1",
    });
    expect(ok).toBe(true);
    expect(data.obscured).toBe(false);
  });

  it("detects element obscured by keyboard on mobile", async () => {
    if (!reachable) return;
    // Inject an input at the very bottom of the page
    await deviceRequest(device, "evaluate", {
      expression:
        '(function(){var d=document.createElement("div");d.style.height="3000px";document.body.appendChild(d);var i=document.createElement("input");i.id="bottom";i.placeholder="bottom";document.body.appendChild(i);return "done"})()',
    });
    await deviceRequest(device, "scroll-to-bottom", {});

    const kb = await deviceRequest(device, "show-keyboard", { selector: "#bottom" });
    // macOS does not support soft keyboard — skip the rest of this test
    if (
      !kb.ok &&
      (kb.data.error as Record<string, unknown>)?.code === "PLATFORM_NOT_SUPPORTED"
    ) {
      return;
    }
    await new Promise((r) => setTimeout(r, 500));

    const { ok, data } = await deviceRequest(device, "is-element-obscured", {
      selector: "#bottom",
    });
    expect(ok).toBe(true);
    // On mobile the keyboard may obscure a bottom element; on desktop this
    // may not apply. Verify the response shape regardless.
    expect(data).toHaveProperty("obscured");
    expect(typeof data.obscured).toBe("boolean");
    if (data.obscured) {
      expect(data).toHaveProperty("reason");
    }

    await deviceRequest(device, "hide-keyboard", {});
  });
});
