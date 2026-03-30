import type { Command } from "commander";
import { registerDiscover } from "./discover.js";
import { registerDevices } from "./devices.js";
import { registerPing } from "./ping.js";

export function registerAllCommands(program: Command): void {
  registerDiscover(program);
  registerDevices(program);
  registerPing(program);
}
