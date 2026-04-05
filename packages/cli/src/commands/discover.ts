import type { Command } from "commander";
import { scanForDevices } from "../discovery/scanner.js";
import { addDevices } from "../discovery/registry.js";
import { print } from "../output/formatter.js";
import type { GlobalOptions } from "../types.js";

export function registerDiscover(program: Command): void {
  program
    .command("discover")
    .description("Scan the local network for Kelpie browser instances")
    .option("--scan-timeout <ms>", "mDNS scan duration in milliseconds", "3000")
    .action(async (opts: { scanTimeout: string }) => {
      const globals = program.opts<GlobalOptions>();
      const duration = Number(opts.scanTimeout);
      const devices = await scanForDevices(duration);
      addDevices(devices);
      print({ devices, count: devices.length }, globals.format);
    });
}
