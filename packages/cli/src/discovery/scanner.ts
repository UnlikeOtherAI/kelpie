import bonjourService from "bonjour-service";
import {
  MDNS_SERVICE_TYPE,
  type MdnsTxtRecord,
  type Platform,
  type RuntimeMode,
} from "@unlikeotherai/kelpie-shared";
import type { DiscoveredDevice } from "../types.js";

const platforms: readonly Platform[] = ["ios", "android", "macos", "linux", "windows"];
interface BonjourServiceRecord {
  txt?: Partial<MdnsTxtRecord>;
  addresses?: string[];
  referer?: { address?: string };
  name: string;
  port: number;
}

interface BonjourBrowser {
  on(event: "up", listener: (service: BonjourServiceRecord) => void): void;
  stop(): void;
}

interface BonjourClient {
  find(opts: { type: string }): BonjourBrowser;
  destroy(): void;
}

type BonjourConstructor = new () => BonjourClient;
type BonjourModule = BonjourConstructor | { Bonjour?: BonjourConstructor; default?: BonjourConstructor };

function parsePlatform(value: string | undefined): Platform {
  const normalized = value?.toLowerCase();
  return platforms.find((platform) => platform === normalized) ?? "ios";
}

function parseRuntimeMode(value: string | undefined): RuntimeMode | undefined {
  const normalized = value?.toLowerCase();
  if (normalized === "gui" || normalized === "headless") {
    return normalized;
  }
  return undefined;
}

export async function scanForDevices(
  duration = 3000,
): Promise<DiscoveredDevice[]> {
  const bonjour = createBonjour();
  const devices: DiscoveredDevice[] = [];

  return new Promise((resolve) => {
    const browser = bonjour.find({ type: MDNS_SERVICE_TYPE.replace("_", "").replace("._tcp", "") });

    browser.on("up", (service) => {
      const device = parseService(service);
      if (!device) return;
      // A multi-homed device answers once per interface. Keep one entry but
      // remember every address so pinned pairings stay reachable.
      const existing = devices.find((d) => d.id === device.id);
      if (existing) {
        existing.addresses = orderAddresses([...(existing.addresses ?? []), ...(device.addresses ?? [])]);
        existing.ip = existing.addresses[0] ?? existing.ip;
        return;
      }
      devices.push(device);
    });

    setTimeout(() => {
      browser.stop();
      bonjour.destroy();
      resolve(devices);
    }, duration);
  });
}

function createBonjour(): BonjourClient {
  const module = bonjourService as unknown as BonjourModule;
  const Bonjour = typeof module === "function" ? module : module.Bonjour ?? module.default;
  if (!Bonjour) {
    throw new TypeError("bonjour-service did not expose a Bonjour constructor");
  }
  return new Bonjour();
}

function addressRank(address: string): number {
  if (!address.includes(":")) return 0;
  return address.toLowerCase().startsWith("fe80") ? 2 : 1;
}

/**
 * Prefer IPv4, then global IPv6, then link-local IPv6 as last resort. Ties
 * sort lexically so the same address set always yields the same first pick.
 */
export function orderAddresses(addresses: string[]): string[] {
  return [...new Set(addresses.filter(Boolean))].sort((a, b) =>
    addressRank(a) - addressRank(b) || a.localeCompare(b));
}

function parseService(service: BonjourServiceRecord): DiscoveredDevice | null {
  const txt = service.txt;
  if (!txt?.id) return null;

  const fallback = service.referer?.address;
  const addresses = orderAddresses(fallback ? [...(service.addresses ?? []), fallback] : service.addresses ?? []);
  const ip = addresses[0];
  if (!ip) return null;

  return {
    id: txt.id,
    name: txt.name ?? service.name,
    ip,
    addresses,
    port: Number(txt.port) || service.port,
    platform: parsePlatform(txt.platform),
    runtimeMode: parseRuntimeMode(txt.runtime_mode),
    engine: txt.engine,
    model: txt.model ?? "Unknown",
    width: Number(txt.width) || 0,
    height: Number(txt.height) || 0,
    version: txt.version ?? "0.0.0",
    lastSeen: Date.now(),
  };
}
