import { API_VERSION_PREFIX } from "@unlikeotherai/kelpie-shared";
import type { DiscoveredDevice } from "../types.js";
import {
  defaultClientName,
  fingerprintFor,
  getSessionCache,
  getTokenStore,
} from "../auth/token-store.js";
import { pair } from "../auth/pairing.js";

export interface HttpResponse<T = unknown> {
  ok: boolean;
  status: number;
  data: T;
}

interface SendOptions {
  /**
   * If false, a `401 UNAUTHORIZED` response is returned to the caller as-is
   * instead of triggering the implicit-pair retry. Used by the `pair`
   * command and unit tests.
   */
  autoPair?: boolean;
}

function toKebabCase(method: string): string {
  return method
    .replace(/([A-Z]+)([A-Z][a-z])/g, "$1-$2")
    .replace(/([a-z])([A-Z])/g, "$1-$2")
    .toLowerCase();
}

function isAbortError(error: unknown): boolean {
  return (error instanceof DOMException && error.name === "AbortError") ||
    (error instanceof Error && error.name === "AbortError");
}

function urlFor(device: DiscoveredDevice, method: string): string {
  const kebabMethod = toKebabCase(method);
  const host = device.ip.includes(":") ? `[${device.ip}]` : device.ip;
  return `http://${host}:${device.port}${API_VERSION_PREFIX}${kebabMethod}`;
}

/** Pull whichever token (session or persistent) we have for this device. */
async function tokenFor(device: DiscoveredDevice): Promise<string | undefined> {
  const sessionToken = getSessionCache().get(device.id, device.ip, device.port);
  if (sessionToken) return sessionToken;
  return getTokenStore().get(device.id, device.ip, device.port);
}

/**
 * Drop tokens for `<deviceId,host,port>` from both caches. Used when the
 * server rejects them — keep the next call free of known-bad credentials.
 */
async function clearTokensFor(device: DiscoveredDevice): Promise<void> {
  getSessionCache().remove(device.id, device.ip, device.port);
  await getTokenStore().remove(device.id, device.ip, device.port);
}

interface RawFetchResult<T> {
  ok: boolean;
  status: number;
  data: T;
}

async function rawFetch<T>(
  url: string,
  body: Record<string, unknown> | undefined,
  token: string | undefined,
  timeout: number,
): Promise<RawFetchResult<T>> {
  const controller = new AbortController();
  const timer = setTimeout(() => {
    controller.abort();
  }, timeout);

  try {
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    if (token) headers.Authorization = `Bearer ${token}`;

    const response = await fetch(url, {
      method: "POST",
      headers,
      body: body ? JSON.stringify(body) : undefined,
      signal: controller.signal,
    });

    const data = (await response.json()) as T;
    return { ok: response.ok, status: response.status, data };
  } catch (error) {
    if (isAbortError(error)) {
      return {
        ok: false,
        status: 408,
        data: {
          success: false,
          error: { code: "TIMEOUT", message: `Request timed out after ${timeout}ms` },
        } as T,
      };
    }
    return {
      ok: false,
      status: 0,
      data: {
        success: false,
        error: {
          code: "NETWORK_ERROR",
          message: error instanceof Error ? error.message : "Network error",
        },
      } as T,
    };
  } finally {
    clearTimeout(timer);
  }
}

/**
 * On a 401, kick off the device pair flow once and retry the original call.
 * The user must approve on-device; we surface a one-line prompt so they
 * know to look at the screen.
 *
 * Returns `true` if a fresh token was obtained.
 */
async function attemptAutoPair(device: DiscoveredDevice): Promise<boolean> {
  // Drop the stale token (if any) before pairing.
  await clearTokensFor(device);

  const store = getTokenStore();
  const clientId = await store.clientId();
  const clientName = defaultClientName();

  process.stderr.write(
    `Device "${device.name}" (${device.ip}:${device.port}) requires pairing. ` +
      `Approve on device when prompted...\n`,
  );

  const result = await pair({ host: device.ip, port: device.port, clientId, clientName });
  if (result.status !== "approved") {
    process.stderr.write(`Pairing not completed: ${result.status}\n`);
    return false;
  }

  if (result.scope === "persistent") {
    await store.set(device.id, device.ip, device.port, result.token);
  } else {
    getSessionCache().set(device.id, device.ip, device.port, result.token);
  }
  return true;
}

export async function sendCommand<T = unknown>(
  device: DiscoveredDevice,
  method: string,
  body?: Record<string, unknown>,
  timeout = 10000,
  options: SendOptions = {},
): Promise<HttpResponse<T>> {
  const url = urlFor(device, method);
  const token = await tokenFor(device);
  const first = await rawFetch<T>(url, body, token, timeout);

  if (first.status !== 401) return first;
  if (options.autoPair === false) return first;

  const paired = await attemptAutoPair(device);
  if (!paired) return first;

  const retryToken = await tokenFor(device);
  return rawFetch<T>(url, body, retryToken, timeout);
}

/**
 * Test seam: expose the fingerprint helper so tests can assert binding logic
 * without re-implementing it.
 */
export { fingerprintFor };
