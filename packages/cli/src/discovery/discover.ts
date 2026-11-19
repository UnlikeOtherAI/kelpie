import { MDNS_SERVICE_TYPE } from "@unlikeotherai/kelpie-shared";
import { probeLocalDevices } from "./local-probe.js";
import { scanForDevices, type MdnsInterface } from "./scanner.js";
import type { DiscoveredDevice } from "../types.js";

export const explicitDeviceHint = "If the browser is reachable directly, use its host:port.";

export async function discoverDevices(timeoutMs = 3000): Promise<{
  devices: DiscoveredDevice[];
  discovery: { mdns: "ok" | "unavailable"; serviceType: string; timeoutMs: number; interfaces: MdnsInterface[] };
  hint?: string;
}> {
  const scan = await scanForDevices(timeoutMs);
  const available = scan.interfaces.some((entry) => !entry.error);
  const discovery = {
    mdns: available ? "ok" as const : "unavailable" as const,
    serviceType: MDNS_SERVICE_TYPE,
    timeoutMs,
    interfaces: scan.interfaces,
  };
  let { devices } = scan;
  let hint: string | undefined;
  if (!available) {
    const failures = scan.interfaces.map(({ address, error }) => `${address}: ${error}`).join(", ");
    hint = `mDNS could not browse ${MDNS_SERVICE_TYPE} (${failures}). ${explicitDeviceHint}`;
  }
  if (devices.length === 0) {
    devices = await probeLocalDevices();
    if (devices.length === 0) {
      hint ??= `No usable replies for ${MDNS_SERVICE_TYPE} in ${timeoutMs} ms and no loopback devices answered. Check whether the browser is advertising and whether the network and firewall allow UDP 5353 multicast. ${explicitDeviceHint}`;
    }
  }
  return { devices, discovery, ...(hint ? { hint } : {}) };
}
