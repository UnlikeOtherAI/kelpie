import { homedir } from "node:os";
import { z } from "zod";
import { CLI_MCP_PORT } from "@unlikeotherai/kelpie-shared";
import { DEFAULT_MCP_BIND_HOST } from "../mcp/transport.js";
import { DESCRIBE_DIGEST_ALGORITHM, digestTools, type WireCatalog, type WireTool } from "../mcp/catalog.js";
import type { DiscoveredDevice } from "../types.js";

/**
 * The `kelpie describe --json` grammar. This is a stability contract for
 * external integrators (first consumer: the Nessie executor): readers must
 * tolerate unknown fields and unknown enum values, and the CLI removes or
 * repurposes nothing without bumping `DESCRIBE_SCHEMA_VERSION`.
 *
 * Security contract: the document may name the answering binary's path and
 * the boolean pairing fact — never a token, never the token store's
 * contents. `detail` strings are redacted of the user's home path.
 */

export const DESCRIBE_SCHEMA_VERSION = 1;

const platformSchema = z.enum(["ios", "android", "macos", "linux", "windows"]);

/** One observed instance. Field names mirror Nessie's KelpieDeviceSchema. */
export const DescribeDeviceSchema = z.object({
  id: z.string(),
  name: z.string(),
  model: z.string().optional(),
  platform: platformSchema,
  runtimeMode: z.enum(["gui", "headless"]).optional(),
  engine: z.string().optional(),
  version: z.string().optional(),
  address: z.string(),
  port: z.number().int(),
  display: z.object({ width: z.number(), height: z.number() }).strict().optional(),
  paired: z.boolean(),
  lastSeenAt: z.string(),
}).strict();

export const DescribeDocumentSchema = z.object({
  schemaVersion: z.literal(DESCRIBE_SCHEMA_VERSION),
  generatedAt: z.string(),
  cli: z.object({
    version: z.string(),
    path: z.string(),
  }).strict(),
  mcp: z.object({
    available: z.boolean(),
    reason: z.enum(["handshake_failed"]).optional(),
    detail: z.string().optional(),
    serverVersion: z.string().optional(),
    stdio: z.object({
      command: z.string(),
      args: z.array(z.string()),
    }).strict(),
    http: z.object({
      command: z.string(),
      args: z.array(z.string()),
      defaultPort: z.number().int(),
      defaultBind: z.string(),
    }).strict(),
  }).strict(),
  tools: z.object({
    count: z.number().int(),
    digest: z.string().regex(/^sha256:[0-9a-f]{64}$/),
    digestAlgorithm: z.literal(DESCRIBE_DIGEST_ALGORITHM),
    catalog: z.array(z.object({
      name: z.string(),
      description: z.string().optional(),
      inputSchema: z.record(z.string(), z.unknown()),
    }).strict()).optional(),
  }).strict().optional(),
  discovery: z.object({
    scanTimeoutMs: z.number().int(),
    mdns: z.enum(["ok", "unavailable"]),
    deviceCount: z.number().int(),
    devices: z.array(DescribeDeviceSchema),
  }).strict(),
}).strict();

export type DescribeDevice = z.infer<typeof DescribeDeviceSchema>;
export type DescribeDocument = z.infer<typeof DescribeDocumentSchema>;

export const DEFAULT_SCAN_TIMEOUT_MS = 3000;

/** Injectable seams so tests can drive every discovery outcome hermetically. */
export interface DescribeDeps {
  cliVersion: string;
  cliPath: string;
  scan: (timeoutMs: number) => Promise<DiscoveredDevice[]>;
  probeLocal: () => Promise<DiscoveredDevice[]>;
  isPaired: (device: DiscoveredDevice) => Promise<boolean>;
  listTools: () => Promise<WireCatalog>;
  now?: () => Date;
}

export interface BuildOptions {
  scanTimeoutMs?: number;
  includeTools?: boolean;
}

/** Error text may embed the user's home path; the document must not leak it. */
function redactHostPaths(message: string): string {
  return message.split(homedir()).join("~");
}

/**
 * Merge mDNS and loopback observations. Dedupe key is `ip:port` — the only
 * key both sources agree on. A loopback entry may still duplicate an mDNS
 * entry for one instance seen at two addresses; both are kept (documented
 * behavior, consumers key on address:port). mDNS entries keep scan order and
 * come first; loopback entries follow, sorted by port.
 */
function mergeDevices(mdns: DiscoveredDevice[], local: DiscoveredDevice[]): DiscoveredDevice[] {
  const seen = new Set<string>();
  const merged: DiscoveredDevice[] = [];
  for (const device of [...mdns, ...local.slice().sort((a, b) => a.port - b.port)]) {
    const key = `${device.ip}:${device.port}`;
    if (seen.has(key)) continue;
    seen.add(key);
    merged.push(device);
  }
  return merged;
}

async function toDescribeDevice(
  device: DiscoveredDevice,
  isPaired: DescribeDeps["isPaired"],
): Promise<DescribeDevice> {
  return {
    id: device.id,
    name: device.name,
    model: device.model,
    platform: device.platform,
    runtimeMode: device.runtimeMode,
    engine: device.engine,
    version: device.version,
    address: device.ip,
    port: device.port,
    display: { width: device.width, height: device.height },
    paired: await isPaired(device),
    lastSeenAt: new Date(device.lastSeen).toISOString(),
  };
}

/**
 * Assemble the describe document. Never throws for an *answerable* state —
 * no devices, mDNS down, or a failed MCP handshake are all answers carried
 * in the document. Throws only when the document itself cannot be built.
 */
export async function buildDescribeDocument(
  options: BuildOptions,
  deps: DescribeDeps,
): Promise<DescribeDocument> {
  const scanTimeoutMs = options.scanTimeoutMs ?? DEFAULT_SCAN_TIMEOUT_MS;
  const now = deps.now ?? (() => new Date());

  let catalog: WireCatalog | undefined;
  let mcpError: { reason: "handshake_failed"; detail: string } | undefined;
  try {
    catalog = await deps.listTools();
  } catch (err) {
    mcpError = {
      reason: "handshake_failed",
      detail: redactHostPaths(err instanceof Error ? err.message : String(err)).slice(0, 300),
    };
  }

  let mdnsDevices: DiscoveredDevice[] = [];
  let mdns: "ok" | "unavailable" = "ok";
  try {
    mdnsDevices = await deps.scan(scanTimeoutMs);
  } catch {
    mdns = "unavailable";
  }

  let localDevices: DiscoveredDevice[] = [];
  try {
    localDevices = await deps.probeLocal();
  } catch {
    // A failed loopback probe is indistinguishable from "nothing local";
    // it must not mask the mDNS results.
  }

  const merged = mergeDevices(mdnsDevices, localDevices);
  const devices = await Promise.all(merged.map((device) => toDescribeDevice(device, deps.isPaired)));

  const document: DescribeDocument = {
    schemaVersion: DESCRIBE_SCHEMA_VERSION,
    generatedAt: now().toISOString(),
    cli: {
      version: deps.cliVersion,
      path: deps.cliPath,
    },
    mcp: {
      available: catalog !== undefined,
      reason: mcpError?.reason,
      detail: mcpError?.detail,
      serverVersion: catalog?.serverVersion,
      stdio: { command: "kelpie", args: ["mcp"] },
      http: {
        command: "kelpie",
        args: ["mcp", "--http", "--port", String(CLI_MCP_PORT), "--bind", DEFAULT_MCP_BIND_HOST],
        defaultPort: CLI_MCP_PORT,
        defaultBind: DEFAULT_MCP_BIND_HOST,
      },
    },
    tools: catalog
      ? {
          count: catalog.tools.length,
          digest: digestTools(catalog.tools),
          digestAlgorithm: DESCRIBE_DIGEST_ALGORITHM,
          catalog: options.includeTools ? catalog.tools : undefined,
        }
      : undefined,
    discovery: {
      scanTimeoutMs,
      mdns,
      deviceCount: devices.length,
      devices,
    },
  };

  // The grammar is a contract; fail loudly here rather than emit a document
  // an integrator cannot parse.
  return DescribeDocumentSchema.parse(document);
}

export type { WireTool };
