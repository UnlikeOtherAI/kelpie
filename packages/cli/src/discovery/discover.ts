import type { DiscoveredDevice } from "../types.js";
import { enrichDevicesWithCapabilities } from "./capabilities.js";
import { probeLocalDevices } from "./local-probe.js";
import { scanForDevices } from "./scanner.js";

/**
 * The one discovery sweep behind both `kelpie discover` and the
 * `kelpie_discover` MCP tool: an mDNS browse, then — when it finds nothing —
 * the loopback probe. mDNS is racy for a same-host Kelpie, and the Windows
 * browser never announces itself at all: its control plane is loopback-only,
 * so an announcement would only advertise an address nobody else can use.
 */
export async function discoverDevices(scanMs: number): Promise<DiscoveredDevice[]> {
  const devices = await enrichDevicesWithCapabilities(await scanForDevices(scanMs));
  if (devices.length > 0) return devices;
  // probeLocalDevices already returns one device per port.
  return probeLocalDevices();
}
