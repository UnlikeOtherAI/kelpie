import type { Command } from "commander";
import { getDevice } from "../discovery/registry.js";
import { sendCommand } from "../client/http-client.js";
import { print } from "../output/formatter.js";
import type { GlobalOptions, DiscoveredDevice } from "../types.js";

export function getGlobals(program: Command): GlobalOptions {
  return program.opts<GlobalOptions>();
}

export function requireDevice(program: Command): DiscoveredDevice | null {
  const globals = getGlobals(program);
  if (!globals.device) {
    print({ success: false, error: { code: "MISSING_DEVICE", message: "Use --device to specify a target device" } }, globals.format);
    process.exitCode = 1;
    return null;
  }
  const device = getDevice(globals.device);
  if (!device) {
    print({ success: false, error: { code: "DEVICE_NOT_FOUND", message: `No device matching "${globals.device}"` } }, globals.format);
    process.exitCode = 4;
    return null;
  }
  return device;
}

export async function deviceCommand(
  program: Command,
  method: string,
  body?: Record<string, unknown>,
): Promise<void> {
  const globals = getGlobals(program);
  const device = requireDevice(program);
  if (!device) return;
  const result = await sendCommand(device, method, body, globals.timeout);
  print(result.data, globals.format);
  if (!result.ok) process.exitCode = 1;
}
