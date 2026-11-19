import { sendCommand } from "../client/http-client.js";
import type { DiscoveredDevice } from "../types.js";

export async function enrichDevicesWithCapabilities(
  devices: DiscoveredDevice[],
  timeout = 1500,
): Promise<DiscoveredDevice[]> {
  const enriched = await Promise.all(
    devices.map(async (device) => {
      try {
        const result = await sendCommand(device, "getCapabilities", undefined, timeout, { autoPair: false });
        if (!result.ok || !(result.data as { success?: boolean }).success) {
          return device;
        }
        return { ...device, capabilities: result.data as DiscoveredDevice["capabilities"] };
      } catch {
        return device;
      }
    }),
  );
  return enriched;
}
