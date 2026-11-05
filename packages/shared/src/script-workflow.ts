import { z } from "zod";
import { BrowserExtractionOptionsSchema } from "./browser-control/observations.js";

/** Strict authored workflows are opt-in; unversioned legacy scripts retain their own admission. */
export const scriptTargetSchema = z.union([
  z.object({ role: z.string().min(1).max(64), name: z.string().min(1).max(512), exact: z.literal(true).default(true) }).strict(),
  z.object({ label: z.string().min(1).max(512), exact: z.literal(true).default(true) }).strict(),
  z.object({ selector: z.string().min(1).max(1024) }).strict(),
  z.object({ x: z.number().nonnegative(), y: z.number().nonnegative() }).strict(),
]);
export type ScriptTarget = z.infer<typeof scriptTargetSchema>;

const timeoutMs = z.number().int().min(1).max(120_000).default(10_000);
const color = z.string().regex(/^#[0-9a-fA-F]{6}$/);
export const tapIndicatorSchema = z.object({
  color: color.default("#3B82F6"),
  radius: z.number().min(2).max(100).default(20),
  durationMs: z.number().int().min(100).max(5000).default(700),
  wobble: z.boolean().default(true),
  fade: z.boolean().default(true),
}).strict();
export const scriptPointerSchema = z.object({
  enabled: z.boolean().default(false),
  curve: z.enum(["s", "c"]).default("s"),
  durationMs: z.number().int().min(0).max(5000).default(350),
  easing: z.literal("ease-in-out").default("ease-in-out"),
}).strict();
export const scriptCaptureSchema = z.object({
  formats: z.array(z.enum(["gif", "video", "screenshots"])).min(1).max(3),
  fps: z.number().int().min(1).max(30).default(15),
  maxWidth: z.number().int().min(64).max(1920).default(1280),
  maxDurationMs: z.number().int().min(100).max(300_000).default(60_000),
  maxBytes: z.number().int().min(1024).max(268_435_456).default(67_108_864),
}).strict().refine(v => new Set(v.formats).size === v.formats.length, "Duplicate capture format");

export const workflowValueSchema = z.union([
  z.string().max(16_000),
  z.object({ input: z.string().min(1).max(64) }).strict(),
  z.object({ secret: z.string().min(1).max(128) }).strict(),
]);
const target = scriptTargetSchema;
const action = <T extends z.ZodRawShape>(shape: T) => z.object(shape).strict();
export const scriptActionSchema = z.discriminatedUnion("action", [
  action({ action: z.literal("navigate"), url: z.string().regex(/^https?:\/\//).max(4096) }),
  action({ action: z.literal("click"), target }),
  action({ action: z.literal("tap"), target }),
  action({ action: z.literal("fill"), target, text: workflowValueSchema, sensitive: z.boolean().optional(), typingDelayMs: z.number().int().min(1).max(1000).optional() }),
  action({ action: z.literal("type"), target, text: workflowValueSchema, sensitive: z.boolean().optional(), typingDelayMs: z.number().int().min(1).max(1000).optional() }),
  action({ action: z.literal("press-key"), key: z.string().min(1).max(64) }),
  action({ action: z.literal("scroll"), deltaX: z.number().default(0), deltaY: z.number() }),
  action({ action: z.literal("wait"), ms: z.number().int().min(0).max(120_000) }),
  action({ action: z.literal("wait-ready"), state: z.enum(["interactive", "complete"]).default("interactive"), selector: z.string().min(1).max(1024).optional(), timeoutMs }),
  action({ action: z.literal("assert"), target, state: z.enum(["visible", "hidden", "enabled"]), timeoutMs }),
  action({ action: z.literal("screenshot"), name: z.string().min(1).max(64).optional() }),
  action({ action: z.literal("commentary"), text: z.string().max(1024), durationMs: z.number().int().min(0).max(30_000).default(3000), position: z.enum(["top", "center", "bottom"]).default("bottom") }),
  action({ action: z.literal("extract"), name: z.string().regex(/^[a-zA-Z][a-zA-Z0-9_]{0,63}$/), params: BrowserExtractionOptionsSchema }),
  action({ action: z.literal("output"), name: z.string().regex(/^[a-zA-Z][a-zA-Z0-9_]{0,63}$/), source: z.enum(["url", "title", "status"]) }),
]);
export const workflowInputSchema = z.object({
  type: z.enum(["string", "number", "boolean"]),
  required: z.boolean().default(true),
}).strict();
export const scriptV1Schema = z.object({
  version: z.literal(1),
  name: z.string().min(1).max(128).optional(),
  tabId: z.string().min(1).max(256),
  sessionId: z.string().min(1).max(256).optional(),
  inputs: z.record(z.string().regex(/^[a-zA-Z][a-zA-Z0-9_]{0,63}$/), workflowInputSchema).optional(),
  actions: z.array(scriptActionSchema).min(1).max(1000),
  capture: scriptCaptureSchema.optional(),
  tapIndicator: tapIndicatorSchema.optional(),
  pointer: scriptPointerSchema.optional(),
  defaultWaitBetweenActions: z.number().int().min(0).max(30_000).default(0),
}).strict();
export type ScriptV1 = z.infer<typeof scriptV1Schema>;
export type ScriptAction = z.infer<typeof scriptActionSchema>;
export type ScriptCapture = z.infer<typeof scriptCaptureSchema>;
export type ScriptPointer = z.infer<typeof scriptPointerSchema>;
export type TapIndicator = z.infer<typeof tapIndicatorSchema>;

export const scriptArtifactRequestSchema = z.object({
  runId: z.string().min(1).max(128),
  artifactId: z.string().min(1).max(128),
  offset: z.number().int().nonnegative().default(0),
  length: z.number().int().min(1).max(1_048_576).default(262_144),
}).strict();
export const scriptArtifactSchema = z.object({
  id: z.string().min(1).max(128),
  mimeType: z.enum(["image/png", "image/gif", "video/mp4"]),
  byteLength: z.number().int().positive(),
  sha256: z.string().regex(/^[a-f0-9]{64}$/),
  partial: z.boolean(),
  width: z.number().int().positive(),
  height: z.number().int().positive(),
  durationMs: z.number().nonnegative().optional(),
  frameCount: z.number().int().nonnegative().optional(),
  droppedFrames: z.number().int().nonnegative().optional(),
  viewport: z.object({ width: z.number().positive(), height: z.number().positive() }).strict().optional(),
  documentId: z.string().min(1).max(256).optional(),
  actionIndex: z.number().int().nonnegative().optional(),
}).strict();
export type ScriptArtifact = z.infer<typeof scriptArtifactSchema>;
const targetRequestBase = {
  target: scriptTargetSchema,
  policy: z.object({ refuseSensitive: z.boolean() }).strict().optional(),
  key: z.string().min(1).max(256),
  token: z.string().min(1).max(128).optional(),
};
export const scriptTargetRequestSchema = z.union([
  z.object({ ...targetRequestBase, token: z.string().min(1).max(128), proveNonInput: z.literal(true),
    dispatch: z.literal(false).optional(), observe: z.literal(false).optional() }).strict(),
  z.object({ ...targetRequestBase, token: z.string().min(1).max(128), postMutation: z.literal(true),
    dispatch: z.literal(false).optional(), observe: z.literal(false).optional() }).strict(),
  z.object({ ...targetRequestBase, dispatch: z.literal(true), observe: z.literal(false).optional() }).strict(),
  z.object({ ...targetRequestBase, dispatch: z.literal(false).optional(), observe: z.literal(true) }).strict(),
  z.object({ ...targetRequestBase, dispatch: z.literal(false).optional(), observe: z.literal(false).optional(),
    edit: z.object({ action: z.enum(["fill", "type"]), text: z.string().max(16_000), requireFocused: z.boolean().optional() }).strict() }).strict(),
  z.object({ ...targetRequestBase, dispatch: z.literal(false).optional(), observe: z.literal(false).optional() }).strict(),
]);
export const scriptArtifactChunkSchema = z.object({
  success: z.literal(true).optional(),
  runId: z.string().min(1).max(128),
  artifactId: z.string().min(1).max(128),
  data: z.string().max(1_398_104).regex(/^[A-Za-z0-9+/]*={0,2}$/),
  offset: z.number().int().nonnegative(),
  nextOffset: z.number().int().nonnegative(),
  eof: z.boolean(),
  mimeType: z.enum(["image/png", "image/gif", "video/mp4"]),
  byteLength: z.number().int().positive(),
  sha256: z.string().regex(/^[a-f0-9]{64}$/),
}).strict();
