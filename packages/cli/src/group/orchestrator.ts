import { sendCommand } from "../client/http-client.js";
import type { DiscoveredDevice } from "../types.js";

export interface DeviceMeta {
  name: string;
  platform: string;
  resolution: string;
}

export interface DeviceResult<T = unknown> {
  device: DeviceMeta;
  success: boolean;
  data?: T;
  error?: { code: string; message: string };
}

export interface GroupResult<T = unknown> {
  command: string;
  deviceCount: number;
  results: DeviceResult<T>[];
  succeeded: number;
  failed: number;
}

export interface SmartQueryResult<T = unknown> {
  command: string;
  deviceCount: number;
  found: ({ device: DeviceMeta } & T)[];
  notFound: { device: DeviceMeta; reason: string }[];
}

function extractError(data: unknown): { code: string; message: string } | undefined {
  if (typeof data === "object" && data !== null && "error" in data) {
    const err = (data as { error: unknown }).error;
    if (
      typeof err === "object" &&
      err !== null &&
      "code" in err &&
      "message" in err &&
      typeof (err as { code: unknown }).code === "string" &&
      typeof (err as { message: unknown }).message === "string"
    ) {
      return err as { code: string; message: string };
    }
  }
  return undefined;
}

function deviceMeta(d: DiscoveredDevice): DeviceMeta {
  return {
    name: d.name,
    platform: d.platform,
    resolution: `${d.width}x${d.height}`,
  };
}

export async function executeGroup<T = unknown>(
  devices: DiscoveredDevice[],
  method: string,
  body: Record<string, unknown>,
  timeout: number,
): Promise<GroupResult<T>> {
  const results = await Promise.allSettled(
    devices.map(async (d) => {
      const response = await sendCommand<T>(d, method, body, timeout);
      return {
        device: deviceMeta(d),
        success: response.ok,
        data: response.ok ? response.data : undefined,
        error: response.ok
          ? undefined
          : extractError(response.data) ?? {
              code: "UNKNOWN",
              message: "Request failed",
            },
      } as DeviceResult<T>;
    }),
  );

  const settled = results.map((r) =>
    r.status === "fulfilled"
      ? r.value
      : ({
          device: { name: "unknown", platform: "unknown", resolution: "0x0" },
          success: false,
          error: { code: "NETWORK_ERROR", message: r.reason instanceof Error ? r.reason.message : "Unknown error" },
        } as DeviceResult<T>),
  );

  return {
    command: method,
    deviceCount: devices.length,
    results: settled,
    succeeded: settled.filter((r) => r.success).length,
    failed: settled.filter((r) => !r.success).length,
  };
}

export async function executeSmartQuery<T extends Record<string, unknown>>(
  devices: DiscoveredDevice[],
  method: string,
  body: Record<string, unknown>,
  timeout: number,
): Promise<SmartQueryResult<T>> {
  const group = await executeGroup<T & { found?: boolean }>(devices, method, body, timeout);

  const found: ({ device: DeviceMeta } & T)[] = [];
  const notFound: { device: DeviceMeta; reason: string }[] = [];

  for (const result of group.results) {
    if (result.success && result.data?.found) {
      const { found: _foundFlag, ...rest } = result.data;
      found.push({ device: result.device, ...rest } as { device: DeviceMeta } & T);
    } else {
      notFound.push({
        device: result.device,
        reason: result.error?.message ?? "Element not found",
      });
    }
  }

  return {
    command: method,
    deviceCount: devices.length,
    found,
    notFound,
  };
}
