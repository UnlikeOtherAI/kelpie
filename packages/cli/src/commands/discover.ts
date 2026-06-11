import type { Command } from "commander";
import { scanForDevices } from "../discovery/scanner.js";
import { enrichDevicesWithCapabilities } from "../discovery/capabilities.js";
import { probeLocalDevices } from "../discovery/local-probe.js";
import { addDevices } from "../discovery/registry.js";
import { print } from "../output/formatter.js";
import type { DiscoveredDevice, GlobalOptions } from "../types.js";

export function registerDiscover(program: Command): void {
  program
    .command("discover")
    .alias("devices")
    .description("Scan the local network for Kelpie browser instances")
    .option("--scan-timeout <ms>", "mDNS scan duration in milliseconds", "3000")
    .action(async (opts: { scanTimeout: string }) => {
      const globals = program.opts<GlobalOptions>();
      const duration = Number(opts.scanTimeout);
      const devices = await enrichDevicesWithCapabilities(await scanForDevices(duration));
      // mDNS is racy; if the browse came up empty, probe localhost so a
      // same-host Kelpie still shows up in `kelpie devices`.
      if (devices.length === 0) {
        devices.push(...dedupeByPort(await probeLocalDevices()));
      }
      addDevices(devices);
      print({ devices, count: devices.length }, globals.format);
    });
}

function dedupeByPort(devices: DiscoveredDevice[]): DiscoveredDevice[] {
  const seen = new Set<number>();
  return devices.filter((device) => {
    if (seen.has(device.port)) {
      return false;
    }
    seen.add(device.port);
    return true;
  });
}
