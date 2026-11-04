import { z } from "zod";

export const automationSessionOptionsSchema = z.object({
  isolation: z.enum(["shared", "isolated"]),
  ttlMs: z.number().int().min(1000).max(3_600_000).default(300_000),
}).strict();
export const automationSessionDescriptionSchema = z.object({
  version: z.literal(1),
  sessionId: z.string().min(1).max(256),
  backend: z.enum(["native", "playwright", "lightpanda"]),
  isolation: z.enum(["shared", "isolated"]),
  ownedTabIds: z.array(z.string().min(1).max(256)).max(1000),
  expiresAt: z.iso.datetime(),
}).strict();
export type AutomationSessionOptions = z.input<typeof automationSessionOptionsSchema>;
export type AutomationSessionDescription = z.infer<typeof automationSessionDescriptionSchema>;
