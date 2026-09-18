import { realpathSync } from "node:fs";
import { resolve } from "node:path";
import type { Command } from "commander";
import { scanForDevices } from "../discovery/scanner.js";
import { probeLocalDevices } from "../discovery/local-probe.js";
import { getSessionCache, getTokenStore } from "../auth/token-store.js";
import { listWireCatalog } from "../mcp/catalog.js";
import {
  buildDescribeDocument,
  DEFAULT_SCAN_TIMEOUT_MS,
  type DescribeDeps,
  type DescribeDocument,
} from "../describe/document.js";
import type { DiscoveredDevice } from "../types.js";

/**
 * `kelpie describe` — one JSON document answering an external integrator's
 * three questions: is Kelpie here, what version, and what can it see.
 *
 *   kelpie describe --json                    stable machine-readable contract
 *   kelpie describe --json --scan-timeout 8000
 *   kelpie describe --json --include-tools    include the full wire catalog
 *
 * Exit 0 means "here is the answer" — including zero devices, mDNS down, or
 * a failed MCP handshake (all carried in the document). Non-zero means the
 * CLI could not answer at all.
 *
 * The document never contains a token or the token store's contents; the
 * pairing fact is exactly `paired: true/false` per instance.
 */

/** Pairing truth, looked up exactly as sendCommand would for this device. */
async function defaultIsPaired(device: DiscoveredDevice): Promise<boolean> {
  if (getSessionCache().get(device.id, device.ip, device.port)) return true;
  return (await getTokenStore().get(device.id, device.ip, device.port)) !== undefined;
}

function answeringBinaryPath(): string {
  const invoked = process.argv[1];
  if (!invoked) return "unknown";
  try {
    return realpathSync(invoked);
  } catch {
    return resolve(invoked);
  }
}

export function defaultDescribeDeps(cliVersion: string): DescribeDeps {
  return {
    cliVersion,
    cliPath: answeringBinaryPath(),
    scan: (timeoutMs) => scanForDevices(timeoutMs),
    probeLocal: () => probeLocalDevices(),
    isPaired: defaultIsPaired,
    listTools: () => listWireCatalog(),
  };
}

function printHumanSummary(document: DescribeDocument): void {
  const lines = [
    `Kelpie CLI ${document.cli.version} (${document.cli.path})`,
    document.mcp.available
      ? `MCP server: available — ${document.tools?.count ?? 0} tools, digest ${document.tools?.digest ?? "n/a"}`
      : `MCP server: unavailable (${document.mcp.reason ?? "unknown"}${document.mcp.detail ? `: ${document.mcp.detail}` : ""})`,
    `Discovery: mDNS ${document.discovery.mdns}, ${document.discovery.deviceCount} instance(s) in ${document.discovery.scanTimeoutMs}ms`,
  ];
  for (const device of document.discovery.devices) {
    lines.push(
      `  ${device.name} [${device.platform}] ${device.address}:${device.port}` +
      ` v${device.version ?? "?"}${device.engine ? ` ${device.engine}` : ""}` +
      ` ${device.paired ? "paired" : "not paired"}`,
    );
  }
  process.stdout.write(`${lines.join("\n")}\n`);
}

export function registerDescribe(program: Command): void {
  program
    .command("describe")
    .description("Machine-readable report: CLI version, MCP catalog digest, discovered instances")
    .option("--json", "Emit the stable JSON document (the integrator contract)")
    .option("--include-tools", "Include the full MCP tool catalog in the document")
    .option("--scan-timeout <ms>", "Discovery budget in milliseconds", String(DEFAULT_SCAN_TIMEOUT_MS))
    .action(async (opts: { json?: boolean; includeTools?: boolean; scanTimeout: string }) => {
      try {
        const document = await buildDescribeDocument(
          {
            scanTimeoutMs: Number(opts.scanTimeout) || DEFAULT_SCAN_TIMEOUT_MS,
            includeTools: opts.includeTools === true,
          },
          defaultDescribeDeps(String(program.version())),
        );
        if (opts.json) {
          process.stdout.write(`${JSON.stringify(document, null, 2)}\n`);
        } else {
          printHumanSummary(document);
        }
      } catch (err) {
        process.stderr.write(
          `kelpie describe: could not produce a report: ${err instanceof Error ? err.message : String(err)}\n`,
        );
        process.exitCode = 1;
      }
    });
}
