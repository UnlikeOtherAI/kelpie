import type { Command } from "commander";
import { deviceCommand, getGlobals } from "./helpers.js";
import { getAllDevices } from "../discovery/registry.js";
import { sendCommand } from "../client/http-client.js";
import { print } from "../output/formatter.js";

export function registerDeviceInfo(program: Command): void {
  program
    .command("info")
    .description("Get full device information")
    .action(async () => {
      const globals = getGlobals(program);
      if (globals.device) {
        await deviceCommand(program, "getDeviceInfo");
      } else {
        const devices = getAllDevices();
        const results = await Promise.all(
          devices.map(async (d) => {
            const r = await sendCommand(d, "getDeviceInfo", undefined, globals.timeout);
            return { device: d.name, ...r.data as object };
          }),
        );
        print({ devices: results }, globals.format);
      }
    });

  program
    .command("viewport")
    .description("Get viewport dimensions")
    .action(async () => { await deviceCommand(program, "getViewport"); });
}
