import { normalizeEndpointUrl } from "../ai/endpoint-url.js";
import { ApiKeyInputError, readApiKeyFromEnv, readApiKeyFromStream } from "../ai/endpoint-secrets.js";

/**
 * Flag parsing for `kelpie ai endpoint add|edit`, kept free of Commander and
 * HTTP so the flag → request-body mapping is testable on its own.
 */

export interface EndpointFlagOptions {
  name?: string;
  baseUrl?: string;
  model?: string;
  contextWindow?: string;
  vision?: string;
  toolCalling?: string;
  jsonSchema?: string;
  apiKeyEnv?: string;
  apiKeyStdin?: boolean;
  clearApiKey?: boolean;
  /** Declared only so a literal `--api-key` is refused with a clear message. */
  apiKey?: string;
}

export interface EndpointSummary {
  id: string;
  name: string;
  baseURL?: string;
  model?: string | null;
}

export type Capabilities = Partial<Record<"contextWindow" | "vision" | "toolCalling" | "jsonSchema", number | boolean | null>>;

export interface SaveFields {
  name?: string;
  baseURL?: string;
  loopback?: boolean;
  model?: string;
  capabilities?: Capabilities;
  apiKey?: string;
  clearApiKey?: boolean;
}

export class EndpointInputError extends Error {
  constructor(readonly code: string, message: string) {
    super(message);
    this.name = "EndpointInputError";
  }
}

const ARGV_KEY_REFUSAL =
  "API keys are never accepted as a command-line value: argv leaks into shell history and process listings. " +
  "Use --api-key-env <VAR> or pipe the key with --api-key-stdin.";

/** `yes` → true, `no` → false, `unknown` → null (clears a user override). */
export function parseTriState(flag: string, value: string): boolean | null {
  switch (value.trim().toLowerCase()) {
    case "yes": return true;
    case "no": return false;
    case "unknown": return null;
    default: throw new EndpointInputError("INVALID_PARAMS", `--${flag} must be yes, no or unknown.`);
  }
}

/** A positive integer token count, or `unset` → null (clears a user override). */
export function parseContextWindow(value: string): number | null {
  const trimmed = value.trim().toLowerCase();
  if (trimmed === "unset") return null;
  if (!/^\d+$/.test(trimmed) || Number(trimmed) < 1 || !Number.isSafeInteger(Number(trimmed))) {
    throw new EndpointInputError("INVALID_PARAMS", "--context-window must be a positive integer or 'unset'.");
  }
  return Number(trimmed);
}

export function buildCapabilities(opts: EndpointFlagOptions): Capabilities | undefined {
  const capabilities: Capabilities = {};
  if (opts.contextWindow !== undefined) capabilities.contextWindow = parseContextWindow(opts.contextWindow);
  if (opts.vision !== undefined) capabilities.vision = parseTriState("vision", opts.vision);
  if (opts.toolCalling !== undefined) capabilities.toolCalling = parseTriState("tool-calling", opts.toolCalling);
  if (opts.jsonSchema !== undefined) capabilities.jsonSchema = parseTriState("json-schema", opts.jsonSchema);
  return Object.keys(capabilities).length > 0 ? capabilities : undefined;
}

/** The key from `--api-key-env` or `--api-key-stdin`; refuses argv values and conflicting sources. */
export async function resolveApiKey(
  opts: EndpointFlagOptions,
  stdin: NodeJS.ReadableStream = process.stdin,
  env: NodeJS.ProcessEnv = process.env,
): Promise<string | undefined> {
  if (opts.apiKey !== undefined) throw new EndpointInputError("API_KEY_ON_COMMAND_LINE", ARGV_KEY_REFUSAL);
  const sources = [opts.apiKeyEnv !== undefined, opts.apiKeyStdin === true, opts.clearApiKey === true].filter(Boolean);
  if (sources.length > 1) {
    throw new EndpointInputError("INVALID_PARAMS", "Use only one of --api-key-env, --api-key-stdin and --clear-api-key.");
  }
  try {
    if (opts.apiKeyEnv !== undefined) return readApiKeyFromEnv(opts.apiKeyEnv, env);
    if (opts.apiKeyStdin) return await readApiKeyFromStream(stdin);
  } catch (error) {
    if (error instanceof ApiKeyInputError) throw new EndpointInputError("INVALID_PARAMS", error.message);
    throw error;
  }
  return undefined;
}

/** Validate every flag (URL included) before any device is contacted. */
export async function parseSaveFields(
  opts: EndpointFlagOptions,
  stdin?: NodeJS.ReadableStream,
  env?: NodeJS.ProcessEnv,
): Promise<SaveFields> {
  const fields: SaveFields = {};
  if (opts.name !== undefined) {
    const name = opts.name.trim();
    if (!name) throw new EndpointInputError("INVALID_PARAMS", "--name must not be empty.");
    fields.name = name;
  }
  if (opts.baseUrl !== undefined) {
    const url = normalizeEndpointUrl(opts.baseUrl);
    if (!url.ok) throw new EndpointInputError(url.code, url.message);
    fields.baseURL = url.baseURL;
    fields.loopback = url.loopback;
  }
  if (opts.model !== undefined) fields.model = opts.model.trim();
  fields.capabilities = buildCapabilities(opts);
  fields.apiKey = await resolveApiKey(opts, stdin, env);
  if (opts.clearApiKey) fields.clearApiKey = true;
  return fields;
}

function compact(body: Record<string, unknown>): Record<string, unknown> {
  return Object.fromEntries(Object.entries(body).filter(([, value]) => value !== undefined));
}

/** `ai-endpoint-save` body for `add`: name and base URL are required. */
export function addBody(fields: SaveFields): Record<string, unknown> {
  if (!fields.name) throw new EndpointInputError("INVALID_PARAMS", "--name is required.");
  if (!fields.baseURL) throw new EndpointInputError("INVALID_PARAMS", "--base-url is required.");
  if (fields.clearApiKey) throw new EndpointInputError("INVALID_PARAMS", "--clear-api-key only applies to edit.");
  return compact({
    name: fields.name,
    baseURL: fields.baseURL,
    apiKey: fields.apiKey,
    model: fields.model === "" ? undefined : fields.model,
    capabilities: fields.capabilities,
  });
}

/**
 * `ai-endpoint-save` body for `edit`. The contract requires `name` and
 * `baseURL` on every save, so unchanged values are carried over from the
 * saved endpoint; the selected model is carried over too unless replaced.
 */
export function editBody(existing: EndpointSummary, fields: SaveFields): Record<string, unknown> {
  const baseURL = fields.baseURL ?? existing.baseURL;
  if (!baseURL) throw new EndpointInputError("INVALID_PARAMS", "The saved endpoint has no base URL; pass --base-url.");
  const model = fields.model ?? existing.model ?? undefined;
  return compact({
    id: existing.id,
    name: fields.name ?? existing.name,
    baseURL,
    apiKey: fields.apiKey,
    clearApiKey: fields.clearApiKey,
    model: model === "" ? undefined : model,
    capabilities: fields.capabilities,
  });
}

/** Exact id, then exact name, then a unique case-insensitive name. */
export function findEndpoint(endpoints: readonly EndpointSummary[], ref: string): EndpointSummary | undefined {
  const byId = endpoints.find((endpoint) => endpoint.id === ref);
  if (byId) return byId;
  const byName = endpoints.find((endpoint) => endpoint.name === ref);
  if (byName) return byName;
  const folded = endpoints.filter((endpoint) => endpoint.name.toLowerCase() === ref.toLowerCase());
  return folded.length === 1 ? folded[0] : undefined;
}

/** `--max-steps`: a whole number from 1 to the contract maximum of 25. */
export function parseMaxSteps(value: string): number {
  const steps = Number(value);
  if (!/^\d+$/.test(value.trim()) || steps < 1 || steps > 25) {
    throw new EndpointInputError("INVALID_PARAMS", "--max-steps must be a whole number from 1 to 25.");
  }
  return steps;
}
