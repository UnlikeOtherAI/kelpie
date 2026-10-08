import { z } from "zod";
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

const aiPlatforms = ["ios", "android", "macos"] as const;
const device = z.string().describe("Device ID, name, or IP address");
const endpointId = z.string().describe("Endpoint id from kelpie_ai_endpoints");

const LOCALHOST =
  "localhost, 127.0.0.1 and [::1] resolve on the device running Kelpie (the Mac running Kelpie, or the phone itself), not on the machine running this MCP client; a phone needs the server's LAN address and the server must listen on the network.";
const NO_FALLBACK =
  "Kelpie never falls back to another endpoint, model, backend or cloud provider: a failing endpoint returns a specific error code (ENDPOINT_UNREACHABLE, ENDPOINT_AUTH_FAILED, ENDPOINT_LOADING, MODEL_NOT_AVAILABLE, …).";
const NO_KEYS = "API keys are never returned by any tool.";

/** Probe calls on the device take up to 8 s. */
const PROBE_TIMEOUT_MS = 30_000;
/** Agent runs chain several model calls, each capped at 900 s on the device. */
const ASK_TIMEOUT_MS = 1_800_000;

function withoutDevice(args: Record<string, unknown>): Record<string, unknown> {
  const { device: _device, ...rest } = args;
  return rest;
}

const capability = (what: string) =>
  z.boolean().nullable().optional().describe(`Declare ${what} support; null clears your override so server metadata or a test decides`);

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

export const aiLoadTool: BrowserToolDef = {
  name: "kelpie_ai_load",
  description: `Select the device's AI backend. Pass a model ID (e.g. 'gemma-4-e2b-q4') or an ollama: prefixed ID, or backend "openai" with a saved endpoint (id or name) and optional model to use an OpenAI-compatible endpoint. Only one backend at a time. Selecting an unreachable or unauthorised endpoint fails and leaves the current backend unchanged. ${NO_FALLBACK}`,
  method: "ai-load",
  timeoutMs: 60_000,
  schema: {
    device,
    model: z.string().optional().describe("Model ID (e.g. 'gemma-4-e2b-q4'), Ollama model (e.g. 'ollama:llava:7b'), or with backend openai the server's model ID exactly as listed"),
    backend: z.enum(["openai"]).optional().describe("'openai' selects a saved OpenAI-compatible endpoint"),
    endpoint: z.string().optional().describe("Saved endpoint id or name (with backend 'openai')"),
  },
  bodyFromArgs: aiLoadBody,
};

export const aiAskTool: BrowserToolDef = {
  name: "kelpie_ai_ask",
  description: `Ask the device's active AI backend about the current page. Use 'context' to auto-gather page data or provide 'text' directly. On an OpenAI-compatible endpoint with no context, text or messages, this runs Kelpie's browser agent: the model reads the pinned tab through semantic text/DOM/accessibility tools (agent requires tool calling; TOOLS_UNVERIFIED means run kelpie_ai_endpoint_test with tools: true). allowActions lets the model click, fill, select and check in the pinned tab only — never navigate, run scripts, read cookies/storage or switch tabs. Text-only models never receive screenshots. The answer comes back with the steps taken; reasoning is returned separately. ${NO_FALLBACK}`,
  method: "ai-infer",
  timeoutMs: ASK_TIMEOUT_MS,
  schema: {
    device,
    prompt: z.string().optional().describe("Question or instruction"),
    audio: z.string().optional().describe("Base64 WAV audio (16kHz mono, max 30s)"),
    context: z.enum(["page_text", "screenshot", "dom", "accessibility"]).optional().describe("Auto-gather page context"),
    text: z.string().optional().describe("Raw text input"),
    maxTokens: z.number().optional().describe("Max tokens (default 512)"),
    temperature: z.number().optional().describe("Temperature (default 0.7)"),
    agent: z.boolean().optional().describe("Run the browser-agent tool loop (OpenAI-compatible endpoints; default true when no context, text or messages are given)"),
    allowActions: z.boolean().optional().describe("Let the agent click, fill, select and check in the pinned tab only (default false: read-only)"),
    tabId: z.string().optional().describe("Tab the agent is pinned to for the whole run (macOS: required when several tabs are open; use kelpie_get_tabs). The model cannot change it."),
    maxSteps: z.number().int().min(1).max(40).optional().describe("Maximum browser tool steps (default 20, maximum 40). Task-list updates are free. When the budget runs out the model gives a final report and the result has completed: false, stopReason: step_limit"),
  },
  bodyFromArgs: aiAskBody,
};

export const aiEndpointTools: BrowserToolDef[] = [
  {
    name: "kelpie_ai_endpoints",
    description: `List the device's saved OpenAI-compatible endpoints with capabilities (each with its source: server, user, test or null for unknown), cached health, the active endpoint and model, and executionHost (what loopback means on that device). ${LOCALHOST} ${NO_KEYS}`,
    method: "ai-endpoints",
    platforms: aiPlatforms,
    timeoutMs: PROBE_TIMEOUT_MS,
    schema: { device },
    bodyFromArgs: withoutDevice,
  },
  {
    name: "kelpie_ai_endpoint_save",
    description: `Add (no id) or update (with id) an OpenAI-compatible endpoint such as llama-server, LM Studio, vLLM or Ollama's /v1. Saving does not connect. The base URL may include a pasted /chat/completions or /models suffix (stripped) and defaults to /v1. ${LOCALHOST} There is no raw API key field: pass apiKeyEnv naming an environment variable of the process running this MCP server, or clearApiKey to remove the stored key. Capabilities you declare override server metadata; text-only models (vision false or unknown) never receive screenshots. ${NO_KEYS}`,
    method: "ai-endpoint-save",
    platforms: aiPlatforms,
    timeoutMs: PROBE_TIMEOUT_MS,
    schema: {
      device,
      id: z.string().optional().describe("Endpoint id to update; omit to add a new endpoint"),
      name: z.string().describe("Display name"),
      baseURL: z.string().describe("http(s)://host[:port][/base], e.g. http://192.168.1.20:1234/v1"),
      model: z.string().optional().describe("Model ID exactly as the server lists it"),
      apiKeyEnv: z.string().optional().describe("Name of an environment variable in the MCP server process holding the API key"),
      clearApiKey: z.boolean().optional().describe("Remove the stored API key"),
      capabilities: z.object({
        contextWindow: z.number().int().positive().nullable().optional().describe("Context window in tokens; null clears your override"),
        vision: capability("image input"),
        toolCalling: capability("tool calling"),
        jsonSchema: capability("JSON-schema output"),
      }).optional().describe("User-declared capabilities"),
    },
    bodyFromArgs: endpointSaveBody,
  },
  {
    name: "kelpie_ai_endpoint_remove",
    description: "Delete a saved endpoint and its stored API key. Removing the active endpoint unloads the openai backend.",
    method: "ai-endpoint-remove",
    platforms: aiPlatforms,
    timeoutMs: PROBE_TIMEOUT_MS,
    schema: { device, id: endpointId },
    bodyFromArgs: withoutDevice,
  },
  {
    name: "kelpie_ai_endpoint_models",
    description: `Fetch GET {base}/models from the device and return model IDs exactly as the server reports them, with context window, vision and load status when the server publishes them. MODEL_DISCOVERY_UNSUPPORTED means the server has no /models; type the model ID instead. ${LOCALHOST}`,
    method: "ai-endpoint-models",
    platforms: aiPlatforms,
    timeoutMs: PROBE_TIMEOUT_MS,
    schema: { device, id: endpointId },
    bodyFromArgs: withoutDevice,
  },
  {
    name: "kelpie_ai_endpoint_test",
    description: `Test an endpoint from the device: reachability, model discovery, an optional short generation (default on) and an optional tool-calling check (tools: true) that records toolCalling with source 'test' — run it with tools: true when kelpie_ai_ask returns TOOLS_UNVERIFIED. ${NO_FALLBACK}`,
    method: "ai-endpoint-test",
    platforms: aiPlatforms,
    timeoutMs: 600_000,
    schema: {
      device,
      id: endpointId,
      model: z.string().optional().describe("Model to test instead of the endpoint's selected model"),
      generate: z.boolean().optional().describe("Run a short generation (default true)"),
      tools: z.boolean().optional().describe("Verify tool calling (default false)"),
    },
    bodyFromArgs: withoutDevice,
  },
  {
    name: "kelpie_ai_endpoint_health",
    description: "Endpoint health: unknown, unreachable, auth_failed, loading, no_model, model_missing, ready or busy, with checkedAt, latencyMs and stale. Defaults to the active endpoint. A cached result older than 90 s reads unknown + stale; refresh probes now.",
    method: "ai-endpoint-health",
    platforms: aiPlatforms,
    timeoutMs: PROBE_TIMEOUT_MS,
    schema: {
      device,
      id: endpointId.optional().describe("Endpoint id (default: the active endpoint)"),
      refresh: z.boolean().optional().describe("Probe now instead of returning the cached state"),
    },
    bodyFromArgs: withoutDevice,
  },
  {
    name: "kelpie_ai_cancel",
    description: "Cancel every in-flight AI request and agent run on the device. Returns how many were cancelled; the cancelled calls fail with INFERENCE_CANCELLED.",
    method: "ai-cancel",
    platforms: aiPlatforms,
    schema: { device },
    bodyFromArgs: withoutDevice,
  },
];
