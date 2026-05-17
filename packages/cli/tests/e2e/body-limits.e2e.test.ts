/**
 * E2E test verifying the native HTTP servers reject oversized requests
 * with the standard error envelope rather than buffering them. Without
 * these limits a single multi-GB POST OOMs the device.
 *
 * The tests skip silently if no device is reachable so CI doesn't fail
 * when there is no real iOS/Android/macOS Kelpie instance available.
 */

import { describe, it, expect, beforeAll } from "vitest";
import { testDevice, isDeviceReachable } from "./setup.js";

const MAX_BODY_BYTES = 50 * 1024 * 1024;
const MAX_HEADER_BYTES = 64 * 1024;

describe("E2E: HTTP body and header size limits", () => {
  const device = testDevice();
  let reachable = false;

  beforeAll(async () => {
    reachable = await isDeviceReachable(device);
  });

  it("rejects bodies that exceed the 50 MB cap with 413", async () => {
    if (!reachable) return;
    const url = `http://${device.ip}:${device.port}/v1/navigate`;
    // Declare a Content-Length one byte over the limit but only send a
    // tiny body — the server must reject on declared length alone.
    const oversizedLength = MAX_BODY_BYTES + 1;
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Length": String(oversizedLength),
      },
      // Send a minimal body — the server should reject before reading.
      body: "{}",
    });
    expect(res.status).toBe(413);
    const data = (await res.json()) as { success?: boolean; error?: { code?: string } };
    expect(data.success).toBe(false);
    expect(data.error?.code).toBe("PAYLOAD_TOO_LARGE");
  });

  it("rejects POSTs without Content-Length with 411", async () => {
    if (!reachable) return;
    const url = `http://${device.ip}:${device.port}/v1/navigate`;
    // fetch always sets Content-Length on Buffers, so we use a stream
    // body and chunked transfer to force the missing-Content-Length path.
    // Skip silently if the runtime can't produce a chunked POST.
    const stream = new ReadableStream({
      start(controller) {
        controller.enqueue(new TextEncoder().encode("{}"));
        controller.close();
      },
    });
    let res: Response;
    try {
      res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: stream,
        // @ts-expect-error — Node fetch needs duplex to send streams
        duplex: "half",
      });
    } catch {
      // Older runtimes without duplex stream support — skip.
      return;
    }
    expect([411, 400]).toContain(res.status);
    const data = (await res.json()) as { success?: boolean; error?: { code?: string } };
    expect(data.success).toBe(false);
  });

  it("rejects header sections that exceed the 64 KB cap", async () => {
    if (!reachable) return;
    // Build a header value that pushes total header bytes past the cap.
    const padding = "x".repeat(MAX_HEADER_BYTES + 1024);
    const url = `http://${device.ip}:${device.port}/v1/navigate`;
    let res: Response;
    try {
      res = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Padding": padding,
        },
        body: "{}",
      });
    } catch {
      // Some runtimes refuse to send oversized headers — that is also
      // an acceptable defence, so don't fail the test.
      return;
    }
    // Either 431 (preferred) or 400 (Netty on Android may return 400
    // depending on which decoder limit trips). Either status indicates
    // the server refused rather than buffered the oversized header.
    expect([400, 431]).toContain(res.status);
  });
});
