import { DEFAULT_PORT } from "@unlikeotherai/kelpie-shared";
import type { DiscoveredDevice } from "../types.js";
import { loadBrowserStore } from "../browser/store.js";

/**
 * mDNS announcements are racy: a Kelpie on the same host is reachable on
 * 127.0.0.1 long before (or without ever) winning the browse. Probe the local
 * /health endpoint directly so the CLI self-heals when discovery misses.
 */

/** How many ports above DEFAULT_PORT to sweep when probing localhost. */
const LOCAL_PORT_SWEEP = 10;

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

function localDevice(
  store: Awaited<ReturnType<typeof loadBrowserStore>>,
  port: number,
): DiscoveredDevice {
  const alias = aliasForPort(store, port);
  const platform = alias?.platform ?? "macos";
  return {
    id: `local:127.0.0.1:${port}`,
    name: alias?.name ?? `localhost:${port}`,
    ip: "127.0.0.1",
    port,
    platform,
    model: `Kelpie ${platform}`,
    width: 0,
    height: 0,
    version: "0.0.0",
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
    ports.map(async (port) => ({ port, reachable: await probeHealth(port) })),
  );
  return results
    .filter((result) => result.reachable)
    .map((result) => localDevice(store, result.port));
}
