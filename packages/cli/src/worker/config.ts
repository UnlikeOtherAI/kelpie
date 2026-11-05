import { readFile } from "node:fs/promises";
import { z } from "zod";
import { LIGHTPANDA_CANDIDATE_METHODS } from "@unlikeotherai/kelpie-shared/browser-control";

const origin = z.string().min(1).max(2048).refine((value) => {
  try { const url = new URL(value); return url.origin === value && ["https:", "http:"].includes(url.protocol); }
  catch { return false; }
});
export const workerConfigSchema = z.object({
  version: z.literal(1),
  backend: z.enum(["playwright", "lightpanda"]),
  endpointEnv: z.string().regex(/^[A-Z_][A-Z0-9_]{0,127}$/),
  allowedOrigins: z.array(origin).min(1).max(100),
  maxSessions: z.number().int().min(1).max(16).default(4),
  maxTabs: z.number().int().min(1).max(16).default(4),
  maxTtlMs: z.number().int().min(1000).max(3_600_000).default(300_000),
  networkBoundary: z.literal("operator-enforced"),
  verifiedLightpandaMethods: z.array(z.enum(LIGHTPANDA_CANDIDATE_METHODS)).max(50).default([]),
  webMcpOrigins: z.array(origin).max(100).default([]),
  webMcpInputEncoding: z.enum(["json-string", "object"]).optional(),
}).strict().superRefine((config, ctx) => {
  if (config.backend === "lightpanda" && config.webMcpOrigins.length) ctx.addIssue({ code: "custom", message: "Site tools are not verified for the Lightpanda backend." });
  if (config.webMcpOrigins.some(value => !config.allowedOrigins.includes(value))) ctx.addIssue({ code: "custom", message: "Site tool origins must be a subset of allowedOrigins." });
  if (config.webMcpOrigins.length && !config.webMcpInputEncoding) ctx.addIssue({ code: "custom", message: "Site tools require an audited input encoding." });
});
export type WorkerConfig = z.infer<typeof workerConfigSchema>;

/** Operator-only startup config. Never use tool inputs to select an endpoint. */
export async function loadWorkerConfig(path: string): Promise<WorkerConfig> {
  const data = await readFile(path);
  if (data.byteLength > 65_536) throw new Error("Worker configuration exceeds its size limit.");
  try { return workerConfigSchema.parse(JSON.parse(data.toString("utf8"))); }
  catch { throw new Error("Invalid worker configuration."); }
}
export function workerEndpoint(config: WorkerConfig, environment: NodeJS.ProcessEnv = process.env): string {
  const endpoint = environment[config.endpointEnv];
  if (!endpoint || endpoint.length > 8192) throw new Error("The configured worker endpoint is unavailable.");
  try {
    const url = new URL(endpoint);
    if (!["ws:", "wss:", "http:", "https:"].includes(url.protocol) || url.username || url.password || url.hash) throw new Error();
    return endpoint;
  } catch { throw new Error("The configured worker endpoint is invalid."); }
}
