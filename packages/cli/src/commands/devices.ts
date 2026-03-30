import type { Command } from "commander";
import { scanForDevices } from "../discovery/scanner.js";
import { addDevices, getAllDevices } from "../discovery/registry.js";
import { print } from "../output/formatter.js";
import type { GlobalOptions } from "../types.js";

export function registerDevices(program: Command): void {
  program
    .command("devices")
    .description("List previously discovered devices")
    .option("--refresh", "Force re-scan before listing")
    .action(async (opts: { refresh?: boolean }) => {
      const globals = program.opts<GlobalOptions>();
      if (opts.refresh) {
        const found = await scanForDevices();
        addDevices(found);
      }
      const devices = getAllDevices();
      print({ devices, count: devices.length }, globals.format);
    });
}
