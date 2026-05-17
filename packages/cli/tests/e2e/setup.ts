/**
 * E2E test helpers for Kelpie integration tests.
 *
 * These tests verify the CLI-to-device pipeline works end-to-end.
 * They require at least one real device (Simulator/Emulator) running Kelpie,
 * or fall back to a local HTTP mock server for CI.
 */

import type { DiscoveredDevice } from "../../src/types.js";
import { DEFAULT_PORT } from "@unlikeotherai/kelpie-shared";

/** Env var to point tests at a specific device without mDNS discovery. */
const DEVICE_HOST = process.env.KELPIE_TEST_HOST ?? "localhost";
const DEVICE_PORT = parseInt(process.env.KELPIE_TEST_PORT ?? String(DEFAULT_PORT), 10);

/**
 * When set to "1", absence of a reachable device is treated as a hard
 * failure rather than a silent skip. CI must set this so platform
 * regressions can't sneak through with green e2e jobs that secretly
 * executed zero assertions. Local developers without a device leave it
 * unset and the e2e tests skip with a one-time warning.
 */
const REQUIRE_DEVICE = process.env.KELPIE_E2E_REQUIRE_DEVICE === "1";

let warnedNoDevice = false;
function warnNoDeviceOnce(device: DiscoveredDevice): void {
  if (warnedNoDevice) return;
  warnedNoDevice = true;
  const target = `http://${device.ip}:${device.port}`;
  console.warn(
    `[kelpie e2e] No device reachable at ${target}. Skipping device-dependent assertions. ` +
      `Set KELPIE_E2E_REQUIRE_DEVICE=1 to make this a hard failure (recommended for CI).`,
  );
}

/** Create a test device descriptor pointing at a real or mock server. */
export function testDevice(overrides: Partial<DiscoveredDevice> = {}): DiscoveredDevice {
  return {
    id: "test-device-001",
    name: "E2E Test Device",
    ip: DEVICE_HOST,
    port: DEVICE_PORT,
    platform: "ios",
    model: "iPhone Simulator",
    width: 390,
    height: 844,
    version: "0.1.0",
    lastSeen: Date.now(),
    ...overrides,
  };
}

/** Send a raw HTTP request to a device's /v1/{method} endpoint. */
export async function deviceRequest(
  device: DiscoveredDevice,
  method: string,
  body: Record<string, unknown> = {},
): Promise<{ ok: boolean; status: number; data: Record<string, unknown> }> {
  const url = `http://${device.ip}:${device.port}/v1/${method}`;
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => { controller.abort(); }, 15000);
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    clearTimeout(timeout);
    const data = (await res.json()) as Record<string, unknown>;
    return { ok: res.ok, status: res.status, data };
  } catch (e) {
    return { ok: false, status: 0, data: { error: String(e) } };
  }
}

/** Check if a device's HTTP server is reachable. */
export async function isDeviceReachable(device: DiscoveredDevice): Promise<boolean> {
  const reachable = await probeDevice(device);
  if (!reachable) {
    if (REQUIRE_DEVICE) {
      const target = `http://${device.ip}:${device.port}`;
      throw new Error(
        `[kelpie e2e] KELPIE_E2E_REQUIRE_DEVICE=1 is set but no device is reachable at ${target}. ` +
          `Boot a Kelpie device (simulator/emulator/physical) or unset the variable to skip locally.`,
      );
    }
    warnNoDeviceOnce(device);
  }
  return reachable;
}

async function probeDevice(device: DiscoveredDevice): Promise<boolean> {
  try {
    const res = await fetch(`http://${device.ip}:${device.port}/health`, {
      signal: AbortSignal.timeout(3000),
    });
    return res.ok;
  } catch {
    return false;
  }
}

/** Wait for a device to become reachable with retries. */
export async function waitForDevice(
  device: DiscoveredDevice,
  timeoutMs = 30000,
): Promise<boolean> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    if (await probeDevice(device)) return true;
    await new Promise((r) => setTimeout(r, 1000));
  }
  if (REQUIRE_DEVICE) {
    const target = `http://${device.ip}:${device.port}`;
    throw new Error(
      `[kelpie e2e] KELPIE_E2E_REQUIRE_DEVICE=1 is set but no device became reachable at ${target} within ${timeoutMs}ms.`,
    );
  }
  warnNoDeviceOnce(device);
  return false;
}

/**
 * Conditional test runner — skips tests if no device is reachable.
 * Use in describe blocks: `const it_ = await conditionalIt(device);`
 */
export function skipUnlessDevice(reachable: boolean) {
  return reachable ? it : it.skip;
}
