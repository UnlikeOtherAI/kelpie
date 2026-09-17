import { createHash } from "node:crypto";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createMcpServer } from "./server.js";

/**
 * The tool catalog exactly as a connected MCP client receives it, plus a
 * stable drift digest. `kelpie describe` reports this digest so an external
 * integrator (e.g. the Nessie executor) can notice a catalog change without
 * shipping 145 schemas on every poll.
 *
 * The catalog is read from a real `McpServer` over an in-memory transport —
 * never re-derived from the tool definitions — so the digest cannot drift
 * from the wire form no matter how the SDK's schema serialization evolves.
 */

export interface WireTool {
  name: string;
  description?: string;
  inputSchema: Record<string, unknown>;
}

export interface WireCatalog {
  tools: WireTool[];
  /** Version the server reported in the MCP handshake, when it connected. */
  serverVersion?: string;
}

/** Structured id for the digest recipe below; bump if the recipe changes. */
export const DESCRIBE_DIGEST_ALGORITHM = "sha256-canonical-json-v1";

/**
 * Canonical JSON: object keys sorted recursively, `undefined` object values
 * dropped, no insignificant whitespace, JS `JSON.stringify` string/number
 * semantics, no Unicode normalization. The digest is SHA-256 over the UTF-8
 * bytes of this serialization. This is the recipe `sha256-canonical-json-v1`
 * names; docs/cli.md publishes it so other TypeScript consumers reproduce
 * the same bytes.
 */
export function canonicalJson(value: unknown): string {
  if (value === undefined) return "";
  if (value === null || typeof value !== "object") {
    return JSON.stringify(value) ?? "null";
  }
  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalJson(item)).join(",")}]`;
  }
  const record = value as Record<string, unknown>;
  const entries = Object.keys(record)
    .filter((key) => record[key] !== undefined)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${canonicalJson(record[key])}`);
  return `{${entries.join(",")}}`;
}

/** `sha256:` digest of the wire catalog, sorted by tool name. */
export function digestTools(tools: readonly WireTool[]): string {
  const entries = tools
    .map((tool) => ({
      name: tool.name,
      description: tool.description,
      inputSchema: tool.inputSchema,
    }))
    .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  return `sha256:${createHash("sha256").update(canonicalJson(entries), "utf8").digest("hex")}`;
}

/**
 * Build the real MCP server, connect a client over InMemoryTransport, and
 * read `tools/list`. A resolved promise is proof the server starts and
 * completes a handshake; a rejection is the `handshake_failed` signal.
 */
export async function listWireCatalog(): Promise<WireCatalog> {
  const server = createMcpServer();
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  const client = new Client({ name: "kelpie-describe", version: "1" }, { capabilities: {} });
  await Promise.all([server.connect(serverTransport), client.connect(clientTransport)]);
  try {
    const tools: WireTool[] = [];
    let cursor: string | undefined;
    do {
      const page = await client.listTools(cursor ? { cursor } : {});
      tools.push(...page.tools);
      cursor = page.nextCursor;
    } while (cursor);
    return { tools, serverVersion: client.getServerVersion()?.version };
  } finally {
    await Promise.allSettled([client.close(), server.close()]);
  }
}
