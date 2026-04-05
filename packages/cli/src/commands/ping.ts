import type { Command } from "commander";
import { getDevice, getAllDevices } from "../discovery/registry.js";
import { sendCommand } from "../client/http-client.js";
import { print } from "../output/formatter.js";
import type { GlobalOptions, DiscoveredDevice } from "../types.js";

export function registerPing(program: Command): void {
  program
    .command("ping")
    .description("Check if a device is reachable")
    .action(async () => {
      const globals = program.opts<GlobalOptions>();
      const timeout = globals.timeout;

      if (globals.device) {
        const device = await getDevice(globals.device);
        if (!device) {
          print(
            { success: false, error: { code: "DEVICE_NOT_FOUND", message: `No device matching "${globals.device}"` } },
            globals.format,
          );
          process.exitCode = 4;
          return;
        }
        const result = await pingDevice(device, timeout);
        print(result, globals.format);
        if (!result.reachable) process.exitCode = 2;
      } else {
        const devices = getAllDevices();
        if (devices.length === 0) {
          print({ success: false, error: { code: "NO_DEVICES", message: "No known devices. Run 'kelpie discover' first." } }, globals.format);
          process.exitCode = 4;
          return;
        }
        const results = await Promise.all(
          devices.map((d) => pingDevice(d, timeout)),
        );
        print({ devices: results }, globals.format);
        if (results.some((r) => !r.reachable)) process.exitCode = 2;
      }
    });
}

async function pingDevice(
  device: DiscoveredDevice,
  timeout: number,
): Promise<{ name: string; ip: string; port: number; reachable: boolean; latency?: number }> {
  const start = Date.now();
  const response = await sendCommand(device, "getDeviceInfo", undefined, timeout);
  const latency = Date.now() - start;

  return {
    name: device.name,
    ip: device.ip,
    port: device.port,
    reachable: response.ok,
    latency: response.ok ? latency : undefined,
  };
}
