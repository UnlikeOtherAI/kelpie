import type { Command } from "commander";
import { getDevice } from "../discovery/registry.js";
import { sendCommand } from "../client/http-client.js";
import { print } from "../output/formatter.js";
import type { GlobalOptions, DiscoveredDevice } from "../types.js";

export function getGlobals(program: Command): GlobalOptions {
  return program.opts<GlobalOptions>();
}

export function explicitGlobalPort(program: Command, globals: GlobalOptions): number | undefined {
  if (program.getOptionValueSource("port") !== "cli") {
    return undefined;
  }
  const rawPort = globals.port as unknown;
  const port = typeof rawPort === "number" ? rawPort : Number.parseInt(String(rawPort), 10);
  return Number.isInteger(port) && port > 0 ? port : undefined;
}

export function withGlobalTabId(
  globals: GlobalOptions,
  body?: Record<string, unknown>,
): Record<string, unknown> | undefined {
  if (!globals.tabId) return body;
  if (body?.tabId) return body;
  return { ...(body ?? {}), tabId: globals.tabId };
}

export async function requireDevice(program: Command): Promise<DiscoveredDevice | null> {
  const globals = getGlobals(program);
  if (globals.device) {
    const device = await getDevice(globals.device, {
      port: explicitGlobalPort(program, globals),
    });
    if (!device) {
      print({ success: false, error: { code: "DEVICE_NOT_FOUND", message: `No device matching "${globals.device}"` } }, globals.format);
      process.exitCode = 4;
      return null;
    }
    return device;
  }

  // No --device flag: auto-scan and pick the sole device if exactly one is found
  const { scanForDevices } = await import("../discovery/scanner.js");
  const { addDevices, getAllDevices } = await import("../discovery/registry.js");
  if (getAllDevices().length === 0) {
    addDevices(await scanForDevices(2500));
  }
  // mDNS is racy; a Kelpie on this host is reachable on 127.0.0.1 even when the
  // browse misses its announcement. Fall back to a direct localhost probe.
  if (getAllDevices().length === 0) {
    const { probeLocalDevices } = await import("../discovery/local-probe.js");
    addDevices(await probeLocalDevices());
  }
  const all = getAllDevices();
  if (all.length === 1) return all[0];
  if (all.length === 0) {
    print({ success: false, error: { code: "NO_DEVICES", message: "No Kelpie devices found on the network" } }, globals.format);
    process.exitCode = 1;
    return null;
  }
  const names = all.map((d) => `  ${d.id}  ${d.name} (${d.platform})`).join("\n");
  print({ success: false, error: { code: "MULTIPLE_DEVICES", message: `Multiple devices found. Use --device to pick one:\n${names}` } }, globals.format);
  process.exitCode = 1;
  return null;
}

export async function deviceCommand(
  program: Command,
  method: string,
  body?: Record<string, unknown>,
): Promise<void> {
  const globals = getGlobals(program);
  const device = await requireDevice(program);
  if (!device) return;
  const result = await sendCommand(device, method, withGlobalTabId(globals, body), globals.timeout);
  print(result.data, globals.format);
  if (!result.ok) process.exitCode = 1;
}
