import type { CommandHelp, HelpField } from "./command-metadata.js";

/**
 * Help metadata for OpenAI-compatible endpoints and the AI commands they
 * extend. Keyed by CLI phrase; `command-aliases.ts` maps the MCP names here.
 */

const aiPlatforms = ["ios", "android", "macos"] as const;

const LOCALHOST =
  "localhost, 127.0.0.1 and [::1] mean the device running Kelpie (the Mac running Kelpie, or the phone itself), not the computer running the CLI or MCP client.";
const NO_FALLBACK = "Kelpie never switches endpoint, model or backend on its own and never routes to a cloud provider.";

const healthField: HelpField = {
  name: "health",
  type: "object",
  description: "Endpoint health",
  fields: [
    { name: "state", type: "enum", values: ["unknown", "unreachable", "auth_failed", "loading", "no_model", "model_missing", "ready", "busy"] },
    { name: "online", type: "boolean" },
    { name: "checkedAt", type: "string" },
    { name: "latencyMs", type: "number" },
    { name: "stale", type: "boolean", description: "true when the cached check is older than 90 s" },
    { name: "message", type: "string" },
  ],
};

const endpointField: HelpField = {
  name: "endpoint",
  type: "object",
  description: "EndpointPublic: id, name, baseURL, loopback, hasApiKey, model, capabilities (value + source), models, modelsDiscoveredAt, health. Never the API key.",
};

const discoveryErrors = ["ENDPOINT_NOT_FOUND", "ENDPOINT_UNREACHABLE", "ENDPOINT_AUTH_FAILED", "ENDPOINT_LOADING", "ENDPOINT_REDIRECT_REFUSED", "ENDPOINT_MALFORMED_RESPONSE", "ENDPOINT_TIMEOUT", "MODEL_DISCOVERY_UNSUPPORTED"];

export const aiEndpointMetadata: Record<string, CommandHelp> = {
  "ai load": { purpose: "Select the device's AI backend", when: "Switching between native, platform, Ollama or a saved OpenAI-compatible endpoint", explanation: `Pass a model ID or an ollama: prefixed ID; for an OpenAI-compatible endpoint send backend "openai" with the endpoint id or name and optional model (CLI: kelpie ai endpoint use). Selecting an unreachable or unauthorised endpoint fails without changing the current backend. ${NO_FALLBACK}`, errors: ["ENDPOINT_NOT_FOUND", "ENDPOINT_UNREACHABLE", "ENDPOINT_AUTH_FAILED", "MODEL_NOT_AVAILABLE"], related: ["ai endpoint use", "ai status", "ai unload"], platforms: aiPlatforms },
  "ai ask": { purpose: "Run inference or the browser agent on the active backend", when: "Asking the device's model about the current page, or letting it inspect (and with allowActions, operate) the pinned tab", explanation: `With an OpenAI-compatible endpoint and no context, text or messages, ai-infer runs Kelpie's agent tool loop over semantic page tools (text, DOM, accessibility, form state). The agent needs tool calling: TOOLS_UNVERIFIED means run kelpie ai endpoint test <name> --tools, or declare --tool-calling yes. allowActions adds click, fill, select and check in the pinned tab only; navigation, scripts, cookies, storage, screenshots and tab management are never offered. Text-only models never receive screenshots. maxSteps defaults to 12, maximum 25. Reasoning is returned separately from the answer. ${NO_FALLBACK}`, errors: ["TOOLS_UNVERIFIED", "TOOLS_NOT_SUPPORTED", "VISION_NOT_SUPPORTED", "AGENT_STEP_LIMIT", "INFERENCE_CANCELLED", "NO_MODEL_SELECTED", "ENDPOINT_UNREACHABLE", "ENDPOINT_STREAM_TRUNCATED", "ENDPOINT_ERROR"], related: ["ai cancel", "ai endpoint test", "ai status"], platforms: aiPlatforms },
  "ai cancel": { purpose: "Cancel in-flight AI work", when: "An agent run or generation is taking too long or the CLI gave up waiting", explanation: "Cancels every in-flight AI request and agent run on the device and returns {cancelled: n}. Cancelled calls fail with INFERENCE_CANCELLED.", related: ["ai ask"], platforms: aiPlatforms, response: [{ name: "cancelled", type: "number", description: "How many requests were cancelled" }] },
  "ai endpoint list": { purpose: "List saved OpenAI-compatible endpoints", when: "Checking which endpoints a device has, which is active, and their cached health and capabilities", explanation: `Returns endpoints (EndpointPublic), activeEndpointId, activeModel and executionHost {platform, loopbackMeans}. ${LOCALHOST} API keys are never returned; hasApiKey says whether one is stored.`, related: ["ai endpoint add", "ai endpoint health", "ai endpoint use"], platforms: aiPlatforms, response: [{ name: "endpoints", type: "array", items: endpointField }, { name: "activeEndpointId", type: "string" }, { name: "activeModel", type: "string" }, { name: "executionHost", type: "object" }] },
  "ai endpoint add": { purpose: "Save an OpenAI-compatible endpoint", when: "Adding llama-server, LM Studio, vLLM, Ollama /v1 or another OpenAI-compatible server the device should use", explanation: `Saves a named endpoint without connecting. The base URL must be http(s) with a host and optional port; pasted /chat/completions or /models suffixes are stripped and an empty path becomes /v1. ${LOCALHOST} A phone needs the server's LAN address, and the server must listen on the network, not only on 127.0.0.1. API keys come only from --api-key-env <VAR> or --api-key-stdin (MCP: apiKeyEnv); they are stored in the device's encrypted secret store and never printed. Capability flags override server metadata: yes, no, or unknown to clear.`, errors: ["INVALID_ENDPOINT_URL", "API_KEY_ON_COMMAND_LINE", "INVALID_PARAMS"], related: ["ai endpoint test", "ai endpoint use", "ai endpoint edit"], platforms: aiPlatforms, response: [endpointField] },
  "ai endpoint edit": { purpose: "Change a saved endpoint", when: "Updating the URL, model, API key or declared capabilities of an endpoint", explanation: "Same flags as add plus --clear-api-key. Omitted flags keep their saved values; capability 'unknown' (or --context-window unset) clears a user override.", errors: ["ENDPOINT_NOT_FOUND", "INVALID_ENDPOINT_URL", "API_KEY_ON_COMMAND_LINE"], related: ["ai endpoint add", "ai endpoint test"], platforms: aiPlatforms, response: [endpointField] },
  "ai endpoint remove": { purpose: "Delete a saved endpoint", when: "An endpoint is no longer needed", explanation: "Deletes the endpoint and its stored API key. Removing the active endpoint unloads the openai backend.", errors: ["ENDPOINT_NOT_FOUND"], related: ["ai endpoint list"], platforms: aiPlatforms },
  "ai endpoint models": { purpose: "Discover an endpoint's models", when: "Choosing a model ID or checking whether a model is loaded", explanation: `The device fetches GET {base}/models and returns IDs exactly as the server lists them, with context window, vision and status when published. An empty list succeeds with a warning. MODEL_DISCOVERY_UNSUPPORTED means type the model ID yourself. ${LOCALHOST}`, errors: discoveryErrors, related: ["ai endpoint test", "ai endpoint use"], platforms: aiPlatforms, response: [{ name: "models", type: "array" }, { name: "warning", type: "string" }] },
  "ai endpoint test": { purpose: "Test an endpoint end to end", when: "After adding an endpoint, after server changes, or when ai ask returns TOOLS_UNVERIFIED", explanation: "Checks reachability and model discovery, runs a short generation (skip with --no-generate) and with --tools verifies tool calling, recording toolCalling with source 'test'. Returns health, models, generation {ok, latencyMs, text} and toolCalling {ok, detail}.", errors: [...discoveryErrors, "MODEL_NOT_AVAILABLE", "TOOLS_NOT_SUPPORTED"], related: ["ai endpoint health", "ai ask"], platforms: aiPlatforms, response: [healthField, { name: "models", type: "array" }, { name: "generation", type: "object" }, { name: "toolCalling", type: "object" }] },
  "ai endpoint health": { purpose: "Show endpoint health", when: "Checking whether the active (or a named) endpoint is ready before running inference", explanation: "Returns the cached health; --refresh probes now. A 200 alone never means ready: ready needs the selected model listed (or a passing generation test when the server has no /models). Results older than 90 s read unknown with stale: true.", errors: ["ENDPOINT_NOT_FOUND"], related: ["ai endpoint test", "ai status"], platforms: aiPlatforms, response: [healthField] },
  "ai endpoint use": { purpose: "Make an endpoint the active AI backend", when: "Switching the device to a saved OpenAI-compatible endpoint and model", explanation: `Sends ai-load {backend: "openai", endpoint, model?}. Fails on unreachable or auth_failed without changing the current backend. ${NO_FALLBACK}`, errors: ["ENDPOINT_NOT_FOUND", "ENDPOINT_UNREACHABLE", "ENDPOINT_AUTH_FAILED", "MODEL_NOT_AVAILABLE"], related: ["ai endpoint list", "ai ask"], platforms: aiPlatforms },
};
