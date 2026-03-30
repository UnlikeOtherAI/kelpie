import { Bonjour, type Service } from "bonjour-service";
import { MDNS_SERVICE_TYPE } from "@unlikeotherai/mollotov-shared";
import type { DiscoveredDevice } from "../types.js";

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

function parseService(service: Service): DiscoveredDevice | null {
  const txt = service.txt as Record<string, string> | undefined;
  if (!txt?.id) return null;

  const ip = service.addresses?.[0] ?? service.referer?.address;
  if (!ip) return null;

  return {
    id: txt.id,
    name: txt.name ?? service.name,
    ip,
    port: Number(txt.port) || service.port,
    platform: (txt.platform as "ios" | "android" | "macos") ?? "ios",
    model: txt.model ?? "Unknown",
    width: Number(txt.width) || 0,
    height: Number(txt.height) || 0,
    version: txt.version ?? "0.0.0",
    lastSeen: Date.now(),
  };
}
