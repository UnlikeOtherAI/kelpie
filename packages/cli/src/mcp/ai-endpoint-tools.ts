import { sharedAiLoadTool, sharedAiAskTool, sharedAiEndpointTools } from "@unlikeotherai/kelpie-shared";
import { normalizeEndpointUrl } from "../ai/endpoint-url.js";
import { ApiKeyInputError, readApiKeyFromEnv } from "../ai/endpoint-secrets.js";
import type { BrowserToolDef } from "./tools.js";

/**
 * MCP tools for user-configured OpenAI-compatible endpoints, plus the AI
 * load/ask tools whose schemas grew for them. Contract:
 * docs/api/ai-endpoints.md.
 */

/** Thrown by `bodyFromArgs` for bad input; the server turns it into an error result. */
export class ToolInputError extends Error {
  constructor(readonly code: string, message: string) {
    super(message);
    this.name = "ToolInputError";
  }
}

function withoutDevice(args: Record<string, unknown>): Record<string, unknown> {
  const { device: _device, ...rest } = args;
  return rest;
}

/** `ai-endpoint-save` body: URL checked early, key read from the named env var in this process. */
export function endpointSaveBody(args: Record<string, unknown>, env: NodeJS.ProcessEnv = process.env): Record<string, unknown> {
  const { apiKeyEnv, clearApiKey, baseURL, ...rest } = withoutDevice(args);
  const url = normalizeEndpointUrl(typeof baseURL === "string" ? baseURL : "");
  if (!url.ok) throw new ToolInputError(url.code, url.message);
  const body: Record<string, unknown> = { ...rest, baseURL: url.baseURL };
  if (typeof apiKeyEnv === "string") {
    if (clearApiKey === true) throw new ToolInputError("INVALID_PARAMS", "Use apiKeyEnv or clearApiKey, not both.");
    try {
      body.apiKey = readApiKeyFromEnv(apiKeyEnv, env);
    } catch (error) {
      if (error instanceof ApiKeyInputError) throw new ToolInputError("INVALID_PARAMS", error.message);
      throw error;
    }
  }
  if (clearApiKey === true) body.clearApiKey = true;
  return body;
}

/** `ai-load` body: `backend: "openai"` needs an endpoint; otherwise a model is required. */
export function aiLoadBody(args: Record<string, unknown>): Record<string, unknown> {
  const body = withoutDevice(args);
  if (body.backend === "openai" && typeof body.endpoint !== "string") {
    throw new ToolInputError("INVALID_PARAMS", "backend \"openai\" needs endpoint (an endpoint id or name).");
  }
  if (body.backend === undefined && typeof body.model !== "string") {
    throw new ToolInputError("INVALID_PARAMS", "Pass model, or backend \"openai\" with endpoint.");
  }
  return body;
}

/** `ai-infer` body: refuses allowActions together with an explicit agent: false. */
export function aiAskBody(args: Record<string, unknown>): Record<string, unknown> {
  const body = withoutDevice(args);
  if (body.allowActions === true && body.agent === false) {
    throw new ToolInputError("INVALID_PARAMS", "allowActions needs the agent; drop agent: false.");
  }
  return body;
}

export const aiLoadTool: BrowserToolDef = { ...sharedAiLoadTool, bodyFromArgs: aiLoadBody };
export const aiAskTool: BrowserToolDef = { ...sharedAiAskTool, bodyFromArgs: aiAskBody };
export const aiEndpointTools: BrowserToolDef[] = sharedAiEndpointTools.map(tool => ({
  ...tool, bodyFromArgs: tool.method === "ai-endpoint-save" ? endpointSaveBody : tool.bodyFromArgs,
}));
