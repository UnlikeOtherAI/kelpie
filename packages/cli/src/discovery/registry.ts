import { DEFAULT_PORT } from "@unlikeotherai/kelpie-shared";
import type { DiscoveredDevice } from "../types.js";
import { loadBrowserStore } from "../browser/store.js";

const devices = new Map<string, DiscoveredDevice>();
let autoScanned = false;

/**
 * Devices that go offline rarely send mDNS goodbye packets. Without a TTL,
 * stale entries linger in the registry forever and the CLI happily routes
 * commands to dead targets. Evict entries whose lastSeen is older than this
 * threshold on every read.
 *
 * 90s matches the upper bound used by typical mDNS announcement intervals
 * (most stacks re-announce every 60-75s); a missing announcement for over
 * 90s is a strong signal the device is gone.
 */
const MDNS_TTL_MS = 90_000;

/** Exposed for tests: time-to-live for unrefreshed device entries (ms). */
export const TTL_MS = MDNS_TTL_MS;

function isExpired(device: DiscoveredDevice, now: number): boolean {
  return now - device.lastSeen > MDNS_TTL_MS;
}

function evictExpired(now: number = Date.now()): void {
  for (const [id, device] of devices) {
    if (isExpired(device, now)) {
      devices.delete(id);
    }
  }
}

export function addDevice(device: DiscoveredDevice): void {
  devices.set(device.id, device);
}

export function addDevices(list: DiscoveredDevice[]): void {
  for (const d of list) addDevice(d);
}

export function removeDevice(id: string): void {
  devices.delete(id);
}

export function getAllDevices(): DiscoveredDevice[] {
  evictExpired();
  return Array.from(devices.values());
}

export async function getDevice(query: string): Promise<DiscoveredDevice | undefined> {
  evictExpired();
  // Auto-scan on first use so --device works without a prior `discover` call
  if (!autoScanned && devices.size === 0) {
    autoScanned = true;
    const { scanForDevices } = await import("./scanner.js");
    const scanned = await scanForDevices(2500);
    addDevices(scanned);
    if (scanned.length === 0) {
      const { probeLocalDevices } = await import("./local-probe.js");
      addDevices(await probeLocalDevices());
    }
  }

  // Priority: ID exact > name exact > name fuzzy > IP exact
  const byId = devices.get(query);
  if (byId) return byId;

  const browserAlias = await getBrowserAliasDevice(query);
  if (browserAlias) return browserAlias;

  const all = getAllDevices();
  const lowerQuery = query.toLowerCase();

  const byNameExact = all.find((d) => d.name.toLowerCase() === lowerQuery);
  if (byNameExact) return byNameExact;

  const byNameFuzzy = all.find((d) =>
    d.name.toLowerCase().includes(lowerQuery),
  );
  if (byNameFuzzy) return byNameFuzzy;

  const byIp = all.find((d) => d.ip === query);
  if (byIp) return byIp;

  const directAddress = getDirectAddressDevice(query);
  if (directAddress) return directAddress;

  return undefined;
}

async function getBrowserAliasDevice(query: string): Promise<DiscoveredDevice | undefined> {
  const store = await loadBrowserStore();
  const running = store.running[query];
  if (!running) {
    return undefined;
  }

  const alias = store.aliases[query];
  return {
    id: `browser:${query}`,
    name: query,
    ip: "127.0.0.1",
    port: running.port,
    platform: alias?.platform ?? "macos",
    model: `Kelpie ${alias?.platform ?? "macos"}`,
    width: 0,
    height: 0,
    version: "0.0.0",
    lastSeen: Date.now(),
  };
}

function getDirectAddressDevice(query: string): DiscoveredDevice | undefined {
  const match = /^(\d{1,3}(?:\.\d{1,3}){3})(?::(\d+))?$/.exec(query);
  if (!match) {
    return undefined;
  }
  return {
    id: `direct:${query}`,
    name: query,
    ip: match[1],
    port: match[2] ? Number(match[2]) : DEFAULT_PORT,
    platform: "linux",
    model: "Kelpie Direct",
    width: 0,
    height: 0,
    version: "0.0.0",
    lastSeen: Date.now(),
  };
}

export function clearDevices(): void {
  devices.clear();
  autoScanned = false;
}

export function deviceCount(): number {
  evictExpired();
  return devices.size;
}
