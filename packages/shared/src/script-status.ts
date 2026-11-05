import { z } from "zod";
import { scriptArtifactSchema } from "./script-workflow.js";

const versions = z.array(z.number().int().positive().max(65_535)).min(1).max(16)
  .refine((values) => new Set(values).size === values.length && values.includes(1), "Unique versions must include 1");
const metadata = {
  success: z.literal(true),
  supportedVersions: versions,
  actionIndex: z.number().int().min(0).max(999).optional(),
  totalActions: z.number().int().min(0).max(1000).optional(),
  elapsedMs: z.number().nonnegative().max(Number.MAX_SAFE_INTEGER).optional(),
  totalDurationMs: z.number().nonnegative().max(Number.MAX_SAFE_INTEGER).optional(),
  abortRequested: z.boolean().optional(),
  artifacts: z.array(scriptArtifactSchema).max(1002).optional(),
  mayHaveCompleted: z.boolean().optional(),
  inputGuarantee: z.string().min(1).max(128).optional(),
  targetGuarantee: z.string().min(1).max(128).optional(),
};
const runId = z.string().min(1).max(128);
const runError = z.object({
  code: z.string().regex(/^[A-Z][A-Z0-9_]{0,127}$/),
  message: z.string().min(1).max(256),
}).strict();
const terminal = { ...metadata, playing: z.literal(false), runId, runError: runError.optional() };
// Query success and terminal run success are deliberately distinct. Failed runs
// remain discoverable through MCP so callers can retrieve partial artifacts.
export const scriptStatusV1Schema = z.union([
  z.object({ ...metadata, state: z.literal("idle"), playing: z.literal(false) }).strict(),
  z.object({ ...metadata, state: z.literal("running"), playing: z.literal(true), runId }).strict(),
  z.object({ ...metadata, state: z.literal("finalizing"), playing: z.literal(true), runId }).strict(),
  z.object({ ...terminal, state: z.literal("completed"), runSuccess: z.literal(true) }).strict(),
  z.object({ ...terminal, state: z.literal("failed"), runSuccess: z.literal(false) }).strict(),
  z.object({ ...terminal, state: z.literal("aborted"), runSuccess: z.literal(false) }).strict(),
]);
export type ScriptStatusV1 = z.infer<typeof scriptStatusV1Schema>;
