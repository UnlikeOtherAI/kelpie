import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";
import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";
import { z } from "zod";

export interface ExtensionEntry {
  description: string;
  schema: z.ZodType<Record<string, unknown>>;
  handler: (args: Record<string, unknown>) => Promise<CallToolResult>;
}
interface Descriptor { name: string; description: string; inputSchema: Record<string, unknown> }
const text = (value: unknown): CallToolResult => ({ content: [{ type: "text", text: JSON.stringify(value) }] });

/** Existing handlers stay registered for compatibility; discovery advertises one callable extension doorway. */
export function registerExtensions(server: McpServer, core: Descriptor, extensions: ReadonlyMap<string, ExtensionEntry>): void {
  const descriptors: Descriptor[] = [core];
  const register = (name: string, description: string, shape: z.ZodRawShape, handler: (args: Record<string, unknown>) => Promise<CallToolResult>): void => {
    server.registerTool(name, { description, inputSchema: shape }, handler);
    descriptors.push({ name, description, inputSchema: z.toJSONSchema(z.object(shape).strict()) });
  };
  register("kelpie_extensions", "List product extension names.", {}, async () => text([...extensions.keys()]));
  register("kelpie_extension_tools", "Fetch schemas for up to 20 extensions before calling kelpie_extension.", { names: z.array(z.string().max(256)).max(20) }, async ({ names }) => text((names as string[]).flatMap((name) => {
    const entry = extensions.get(name);
    return entry ? [{ name, description: entry.description, inputSchema: z.toJSONSchema(entry.schema) }] : [];
  })));
  register("kelpie_extension", "Call a discovered product extension using its documented arguments.", { name: z.string().min(1).max(256), arguments: z.record(z.string(), z.unknown()) }, async (args) => {
    const entry = extensions.get(args.name as string);
    const parsed = entry?.schema.safeParse(args.arguments);
    if (!entry || !parsed?.success) return { isError: true, content: [{ type: "text", text: "Unknown extension or invalid arguments. Fetch its schema before continuing." }] };
    return entry.handler(parsed.data);
  });
  server.server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: descriptors }));
}
