import { API_VERSION_PREFIX } from "@unlikeotherai/kelpie-shared";
import type { DiscoveredDevice } from "../types.js";

export interface HttpResponse<T = unknown> {
  ok: boolean;
  status: number;
  data: T;
}

function toKebabCase(method: string): string {
  return method
    .replace(/([A-Z]+)([A-Z][a-z])/g, "$1-$2")
    .replace(/([a-z])([A-Z])/g, "$1-$2")
    .toLowerCase();
}

export async function sendCommand<T = unknown>(
  device: DiscoveredDevice,
  method: string,
  body?: Record<string, unknown>,
  timeout: number = 10000,
): Promise<HttpResponse<T>> {
  const kebabMethod = toKebabCase(method);
  const host = device.ip.includes(":") ? `[${device.ip}]` : device.ip;
  const url = `http://${host}:${device.port}${API_VERSION_PREFIX}${kebabMethod}`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeout);

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: body ? JSON.stringify(body) : undefined,
      signal: controller.signal,
    });

    const data = (await response.json()) as T;
    return { ok: response.ok, status: response.status, data };
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
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
