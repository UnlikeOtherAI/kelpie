import { DEFAULT_PORT } from "@unlikeotherai/kelpie-shared";
import type { DiscoveredDevice } from "../types.js";
import { loadBrowserStore } from "../browser/store.js";

const devices = new Map<string, DiscoveredDevice>();
let autoScanned = false;

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
  return Array.from(devices.values());
}

export async function getDevice(query: string): Promise<DiscoveredDevice | undefined> {
  // Auto-scan on first use so --device works without a prior `discover` call
  if (!autoScanned && devices.size === 0) {
    autoScanned = true;
    const { scanForDevices } = await import("./scanner.js");
    addDevices(await scanForDevices(2500));
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
}

export function deviceCount(): number {
  return devices.size;
}
