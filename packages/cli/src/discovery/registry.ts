import type { DiscoveredDevice } from "../types.js";

const devices = new Map<string, DiscoveredDevice>();

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

export function getDevice(query: string): DiscoveredDevice | undefined {
  // Priority: ID exact > name exact > name fuzzy > IP exact
  const byId = devices.get(query);
  if (byId) return byId;

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

  return undefined;
}

export function clearDevices(): void {
  devices.clear();
}

export function deviceCount(): number {
  return devices.size;
}
