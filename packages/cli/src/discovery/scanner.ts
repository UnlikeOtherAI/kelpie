import { Bonjour, type Service } from "bonjour-service";
import {
  MDNS_SERVICE_TYPE,
  type MdnsTxtRecord,
  type Platform,
  type RuntimeMode,
} from "@unlikeotherai/kelpie-shared";
import type { DiscoveredDevice } from "../types.js";

const platforms: readonly Platform[] = ["ios", "android", "macos", "linux", "windows"];

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
  duration: number = 3000,
): Promise<DiscoveredDevice[]> {
  const bonjour = new Bonjour();
  const devices: DiscoveredDevice[] = [];
  const seen = new Set<string>();

  return new Promise((resolve) => {
    const browser = bonjour.find({ type: MDNS_SERVICE_TYPE.replace("_", "").replace("._tcp", "") });

    browser.on("up", (service: Service) => {
      const device = parseService(service);
      if (device && !seen.has(device.id)) {
        seen.add(device.id);
        devices.push(device);
      }
    });

    setTimeout(() => {
      browser.stop();
      bonjour.destroy();
      resolve(devices);
    }, duration);
  });
}

/** Prefer IPv4, then global IPv6, then link-local IPv6 as last resort. */
function pickAddress(addresses: string[], fallback?: string): string | undefined {
  const all = fallback ? [...addresses, fallback] : addresses;
  const ipv4 = all.find((a) => !a.includes(":"));
  if (ipv4) return ipv4;
  const globalV6 = all.find((a) => a.includes(":") && !a.startsWith("fe80"));
  if (globalV6) return globalV6;
  return all[0];
}

function parseService(service: Service): DiscoveredDevice | null {
  const txt = service.txt as Partial<MdnsTxtRecord> | undefined;
  if (!txt?.id) return null;

  const ip = pickAddress(service.addresses ?? [], service.referer?.address);
  if (!ip) return null;

  return {
    id: txt.id,
    name: txt.name ?? service.name,
    ip,
    port: Number(txt.port) || service.port,
    platform: parsePlatform(txt.platform),
    runtimeMode: parseRuntimeMode(txt.runtime_mode),
    model: txt.model ?? "Unknown",
    width: Number(txt.width) || 0,
    height: Number(txt.height) || 0,
    version: txt.version ?? "0.0.0",
    lastSeen: Date.now(),
  };
}
