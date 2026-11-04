import { z } from "zod";
import { boundedWebMcpJson } from "./webmcp-json.js";

const origin = z.string().min(1).max(2048).refine((value) => {
  try { const url = new URL(value); return url.origin === value && ["https:", "http:"].includes(url.protocol); }
  catch { return false; }
}, "Use an exact HTTP(S) origin.");
export const webMcpDiscoverParamsSchema = z.object({
  origin,
  maxTools: z.number().int().min(1).max(50).default(20),
  maxChars: z.number().int().min(256).max(65_536).default(16_384),
}).strict();
export const webMcpCallParamsSchema = z.object({
  origin,
  ref: z.string().min(1).max(256),
  input: z.unknown().superRefine((value, ctx) => {
    try { boundedWebMcpJson(value, { maxBytes: 16_384, maxDepth: 8, maxProperties: 512, objectOnly: true }); }
    catch { ctx.addIssue({ code: "custom", message: "Use a bounded plain JSON input object." }); }
  }).default({}),
  timeoutMs: z.number().int().min(1).max(30_000).default(10_000),
}).strict();
export type WebMcpDiscoverParams = z.input<typeof webMcpDiscoverParamsSchema>;
export type WebMcpCallParams = z.input<typeof webMcpCallParamsSchema>;
export interface WebMcpIdentity { sessionId: string; origin: string; documentGeneration: string }
export const webMcpDiscoverySchema = z.object({
  available: z.boolean(), reason: z.string().max(80).optional(), origin,
  documentGeneration: z.string().min(1).max(256), untrusted: z.literal(true),
  tools: z.array(z.object({ ref: z.string().min(1).max(256), name: z.string().min(1).max(128),
    description: z.string().max(2048), inputSchema: z.unknown().optional(), annotations: z.unknown().optional() }).strict()).max(50),
  truncated: z.boolean(),
}).strict();
export interface WebMcpTool {
  ref: string; name: string; description: string; inputSchema?: unknown;
  annotations?: unknown;
}
export interface WebMcpDiscovery {
  available: boolean; reason?: string; origin: string; documentGeneration: string;
  untrusted: true; tools: WebMcpTool[]; truncated: boolean;
}
