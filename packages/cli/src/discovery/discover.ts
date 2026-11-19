import { MDNS_SERVICE_TYPE } from "@unlikeotherai/kelpie-shared";
import { probeLocalDevices } from "./local-probe.js";
import { scanForDevices } from "./scanner.js";
import type { DiscoveredDevice } from "../types.js";

export const explicitDeviceHint = "If the browser is reachable directly, use its host:port.";

export async function discoverDevices(timeoutMs = 3000): Promise<{
  devices: DiscoveredDevice[];
  discovery: { mdns: "ok" | "unavailable"; serviceType: string; timeoutMs: number };
  hint?: string;
}> {
  const discovery = { mdns: "ok" as "ok" | "unavailable", serviceType: MDNS_SERVICE_TYPE, timeoutMs };
  let devices: DiscoveredDevice[];
  let hint: string | undefined;
  try {
    devices = await scanForDevices(timeoutMs);
  } catch (error) {
    discovery.mdns = "unavailable";
    const code = (error as NodeJS.ErrnoException | undefined)?.code;
    hint = `mDNS could not browse ${MDNS_SERVICE_TYPE}${code ? ` (${code})` : ""}. ${explicitDeviceHint}`;
    devices = [];
  }
  if (devices.length === 0) {
    devices = await probeLocalDevices();
    if (devices.length === 0) {
      hint ??= `No usable replies for ${MDNS_SERVICE_TYPE} in ${timeoutMs} ms and no loopback devices answered. ${explicitDeviceHint}`;
    }
  }
  return { devices, discovery, ...(hint ? { hint } : {}) };
}
