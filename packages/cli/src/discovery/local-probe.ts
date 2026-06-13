import { API_VERSION_PREFIX, DEFAULT_PORT, type Platform } from "@unlikeotherai/kelpie-shared";
import type { DiscoveredDevice } from "../types.js";
import { loadBrowserStore } from "../browser/store.js";

/**
 * mDNS announcements are racy: a Kelpie on the same host is reachable on
 * 127.0.0.1 long before (or without ever) winning the browse. Probe the local
 * /health endpoint directly so the CLI self-heals when discovery misses.
 */

/** How many ports above DEFAULT_PORT to sweep when probing localhost. */
const LOCAL_PORT_SWEEP = 10;

const platforms: readonly Platform[] = ["ios", "android", "macos", "linux", "windows"];

interface DeviceInfoPayload {
  name?: string;
  platform?: string;
  version?: string;
  device?: {
    id?: string;
    name?: string;
    model?: string;
    platform?: string;
  };
  display?: {
    width?: number;
    height?: number;
  };
  network?: {
    port?: number;
  };
  app?: {
    version?: string;
  };
}

/** Probe a single localhost port's /health endpoint. Returns false on any error. */
export async function probeHealth(port: number, timeoutMs = 600): Promise<boolean> {
  const controller = new AbortController();
  const timer = setTimeout(() => {
    controller.abort();
  }, timeoutMs);
  try {
    const res = await fetch(`http://127.0.0.1:${port}/health`, { signal: controller.signal });
    return res.ok;
  } catch {
    return false;
  } finally {
    clearTimeout(timer);
  }
}

export async function probeDeviceInfo(
  port: number,
  timeoutMs = 1000,
): Promise<DeviceInfoPayload | undefined> {
  const controller = new AbortController();
  const timer = setTimeout(() => {
    controller.abort();
  }, timeoutMs);
  try {
    const res = await fetch(`http://127.0.0.1:${port}${API_VERSION_PREFIX}get-device-info`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{}",
      signal: controller.signal,
    });
    if (!res.ok) return undefined;
    return await res.json() as DeviceInfoPayload;
  } catch {
    return undefined;
  } finally {
    clearTimeout(timer);
  }
}

/** Candidate ports: every recorded running port plus the default sweep range. */
function candidatePorts(store: Awaited<ReturnType<typeof loadBrowserStore>>): number[] {
  const ports = new Set<number>();
  for (const running of Object.values(store.running)) {
    ports.add(running.port);
  }
  for (let i = 0; i < LOCAL_PORT_SWEEP; i++) {
    ports.add(DEFAULT_PORT + i);
  }
  return Array.from(ports);
}

/** Reverse-lookup the alias whose running port matches, for naming/platform. */
function aliasForPort(
  store: Awaited<ReturnType<typeof loadBrowserStore>>,
  port: number,
): { name: string; platform: DiscoveredDevice["platform"] } | undefined {
  for (const [name, running] of Object.entries(store.running)) {
    if (running.port === port) {
      return { name, platform: store.aliases[name]?.platform ?? "macos" };
    }
  }
  return undefined;
}

function parsePlatform(value: string | undefined, fallback: DiscoveredDevice["platform"]): Platform {
  const normalized = value?.toLowerCase();
  return platforms.find((platform) => platform === normalized) ?? fallback;
}

function localDevice(
  store: Awaited<ReturnType<typeof loadBrowserStore>>,
  port: number,
  info: DeviceInfoPayload,
): DiscoveredDevice {
  const alias = aliasForPort(store, port);
  const platform = parsePlatform(info.device?.platform ?? info.platform, alias?.platform ?? "macos");
  return {
    id: `local:127.0.0.1:${port}`,
    name: alias?.name ?? info.device?.name ?? info.name ?? `localhost:${port}`,
    ip: "127.0.0.1",
    port,
    platform,
    model: info.device?.model ?? `Kelpie ${platform}`,
    width: info.display?.width ?? 0,
    height: info.display?.height ?? 0,
    version: info.app?.version ?? info.version ?? "0.0.0",
    lastSeen: Date.now(),
  };
}

/**
 * Probe localhost for reachable Kelpie instances. Candidate ports are the union
 * of every recorded running port and DEFAULT_PORT..DEFAULT_PORT+9, probed in
 * parallel. Deduped by port.
 */
export async function probeLocalDevices(): Promise<DiscoveredDevice[]> {
  const store = await loadBrowserStore();
  const ports = candidatePorts(store);
  const results = await Promise.all(
    ports.map(async (port) => {
      if (!await probeHealth(port)) {
        return { port, info: undefined };
      }
      return { port, info: await probeDeviceInfo(port) };
    }),
  );
  return results
    .filter((result): result is { port: number; info: DeviceInfoPayload } => result.info !== undefined)
    .map((result) => localDevice(store, result.port, result.info));
}
