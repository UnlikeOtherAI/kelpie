import { isIP } from "node:net";
import { DEFAULT_PORT } from "@unlikeotherai/kelpie-shared";
import type { DiscoveredDevice } from "../types.js";
import { loadBrowserStore } from "../browser/store.js";
import { discoverDevices } from "./discover.js";

const devices = new Map<string, DiscoveredDevice>();
let discoveryInFlight: Promise<void> | undefined;

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

export interface DeviceLookupOptions {
  port?: number;
}

export async function refreshDevicesIfEmpty(): Promise<DiscoveredDevice[]> {
  if (getAllDevices().length === 0) {
    discoveryInFlight ??= discoverDevices(2500)
      .then(({ devices: found }) => { addDevices(found); })
      .finally(() => { discoveryInFlight = undefined; });
    await discoveryInFlight;
  }
  return getAllDevices();
}

export async function getDevice(
  query: string,
  options: DeviceLookupOptions = {},
): Promise<DiscoveredDevice | undefined> {
  const address = parseAddressQuery(query, options.port);
  if (address?.explicitPort) {
    return resolveAddress(address, getAllDevices());
  }

  const all = await refreshDevicesIfEmpty();
  if (address) return resolveAddress(address, all);
  if (!query) return all.length === 1 ? all[0] : undefined;

  const byId = devices.get(query);
  if (byId) return byId;

  const browserAlias = await getBrowserAliasDevice(query);
  if (browserAlias) return browserAlias;

  const lowerQuery = query.toLowerCase();

  const byNameExact = all.find((d) => d.name.toLowerCase() === lowerQuery);
  if (byNameExact) return byNameExact;

  const byNameFuzzy = all.find((d) =>
    d.name.toLowerCase().includes(lowerQuery),
  );
  if (byNameFuzzy) return byNameFuzzy;

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

interface AddressQuery {
  host: string;
  port: number;
  explicitPort: boolean;
}

function parseAddressQuery(query: string, preferredPort?: number): AddressQuery | undefined {
  const bracketed = /^\[([^\]]+)\](?::(\d+))?$/.exec(query);
  const hostPort = /^([a-z\d](?:[a-z\d.-]*[a-z\d.])?):(\d+)$/i.exec(query);
  const host = (bracketed?.[1] ?? hostPort?.[1] ?? query).toLowerCase();
  if (!isIP(host) && !hostPort) return undefined;
  const typedPort = bracketed?.[2] ?? hostPort?.[2];
  const port = typedPort === undefined ? preferredPort ?? DEFAULT_PORT : Number(typedPort);
  if (!Number.isInteger(port) || port < 1 || port > 65535) return undefined;
  return { host, port, explicitPort: typedPort !== undefined || preferredPort !== undefined };
}

function resolveAddress(address: AddressQuery, known: DiscoveredDevice[]): DiscoveredDevice {
  const { host, port, explicitPort } = address;
  const matches = known.filter((device) => device.ip.toLowerCase() === host);
  const match = matches.find((device) => device.port === port) ?? (explicitPort ? undefined : matches[0]);
  if (match) return { ...match, explicitAddress: true };
  const label = `${host.includes(":") ? `[${host}]` : host}:${port}`;
  return {
    id: `direct:${host}:${port}`,
    name: label,
    ip: host,
    port,
    explicitAddress: true,
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
}

export function deviceCount(): number {
  evictExpired();
  return devices.size;
}
