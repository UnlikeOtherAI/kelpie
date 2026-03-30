/**
 * E2E test helpers for Mollotov integration tests.
 *
 * These tests verify the CLI-to-device pipeline works end-to-end.
 * They require at least one real device (Simulator/Emulator) running Mollotov,
 * or fall back to a local HTTP mock server for CI.
 */

import type { DiscoveredDevice } from "../../src/types.js";
import { DEFAULT_PORT } from "@unlikeotherai/mollotov-shared";

/** Env var to point tests at a specific device without mDNS discovery. */
const DEVICE_HOST = process.env.MOLLOTOV_TEST_HOST ?? "localhost";
const DEVICE_PORT = parseInt(process.env.MOLLOTOV_TEST_PORT ?? String(DEFAULT_PORT), 10);

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
    const timeout = setTimeout(() => controller.abort(), 15000);
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
    if (await isDeviceReachable(device)) return true;
    await new Promise((r) => setTimeout(r, 1000));
  }
  return false;
}

/**
 * Conditional test runner — skips tests if no device is reachable.
 * Use in describe blocks: `const it_ = await conditionalIt(device);`
 */
export function skipUnlessDevice(reachable: boolean) {
  return reachable ? it : it.skip;
}
