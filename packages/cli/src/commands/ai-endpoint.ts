import { Option, type Command } from "commander";
import { sendCommand } from "../client/http-client.js";
import { redactSecrets } from "../ai/endpoint-secrets.js";
import { print } from "../output/formatter.js";
import type { DiscoveredDevice } from "../types.js";
import { commandTimeout, getGlobals, requireDevice } from "./helpers.js";
import {
  EndpointInputError,
  addBody,
  editBody,
  findEndpoint,
  parseSaveFields,
  type EndpointFlagOptions,
  type EndpointSummary,
  type SaveFields,
} from "./ai-endpoint-input.js";

/**
 * `kelpie ai endpoint …` — user-configured OpenAI-compatible endpoints.
 * Contract: docs/api/ai-endpoints.md.
 *
 * The device is authoritative for validation, health and capabilities; the
 * CLI validates flags early, resolves endpoint names to ids, and redacts every
 * printed result so an API key can never reach the terminal.
 */

/** Device-side probes take up to 8 s; leave headroom for the HTTP hop. */
const PROBE_TIMEOUT_MS = 30_000;
/** Generation test: 180 s time-to-first-byte plus a tool-calling round. */
const GENERATION_TEST_TIMEOUT_MS = 600_000;
/** Selecting an endpoint checks reachability before switching. */
const LOAD_TIMEOUT_MS = 60_000;

interface CallSpec {
  method: string;
  body: Record<string, unknown>;
  timeoutMs: number;
  secrets?: readonly string[];
}

type RefAction = (endpoint: EndpointSummary) => CallSpec;

function fail(program: Command, code: string, message: string): void {
  print({ success: false, error: { code, message } }, getGlobals(program).format);
  process.exitCode = 1;
}

function reportInputError(program: Command, error: unknown): void {
  if (error instanceof EndpointInputError) {
    fail(program, error.code, error.message);
    return;
  }
  throw error;
}

async function call(program: Command, device: DiscoveredDevice, spec: CallSpec): Promise<void> {
  const timeout = commandTimeout(program, spec.timeoutMs);
  const result = await sendCommand(device, spec.method, spec.body, timeout);
  print(redactSecrets(result.data, spec.secrets ?? []), getGlobals(program).format);
  if (!result.ok) process.exitCode = 1;
}

async function listEndpoints(program: Command, device: DiscoveredDevice): Promise<EndpointSummary[] | undefined> {
  const result = await sendCommand<{ endpoints?: EndpointSummary[] }>(device, "ai-endpoints", {}, commandTimeout(program, PROBE_TIMEOUT_MS));
  if (!result.ok || !Array.isArray(result.data.endpoints)) {
    print(redactSecrets(result.data), getGlobals(program).format);
    process.exitCode = 1;
    return undefined;
  }
  return result.data.endpoints;
}

/** Resolve `<endpoint>` (id or name) on the device, then run the call built from it. */
async function withEndpoint(program: Command, ref: string, build: RefAction): Promise<void> {
  const device = await requireDevice(program);
  if (!device) return;
  const endpoints = await listEndpoints(program, device);
  if (!endpoints) return;
  const endpoint = findEndpoint(endpoints, ref);
  if (!endpoint) {
    const known = endpoints.map((entry) => `${entry.name} (${entry.id})`).join(", ") || "none saved";
    fail(program, "ENDPOINT_NOT_FOUND", `No endpoint matches "${ref}". Saved endpoints: ${known}.`);
    return;
  }
  try {
    await call(program, device, build(endpoint));
  } catch (error) {
    reportInputError(program, error);
  }
}

function loopbackNote(fields: SaveFields): void {
  if (!fields.loopback) return;
  process.stderr.write(
    `Note: ${fields.baseURL ?? "this URL"} is a loopback address. It resolves on the device running Kelpie ` +
      "(the Mac running Kelpie, or the phone itself), not on this computer.\n",
  );
}

function secretsOf(fields: SaveFields): string[] {
  return fields.apiKey ? [fields.apiKey] : [];
}

function addSaveOptions(command: Command): Command {
  return command
    .option("--name <name>", "Display name for the endpoint")
    .option("--base-url <url>", "Base URL, e.g. http://192.168.1.20:1234/v1 (localhost means the Kelpie device)")
    .option("--model <id>", "Model ID to select, exactly as the server lists it")
    .option("--context-window <n|unset>", "Declare the context window in tokens, or 'unset' to clear your override")
    .option("--vision <yes|no|unknown>", "Declare image input support ('unknown' clears your override)")
    .option("--tool-calling <yes|no|unknown>", "Declare tool-calling support ('unknown' clears your override)")
    .option("--json-schema <yes|no|unknown>", "Declare JSON-schema output support ('unknown' clears your override)")
    .option("--api-key-env <VAR>", "Read the API key from this environment variable")
    .option("--api-key-stdin", "Read the API key from stdin (pipe it; it is never echoed)")
    .addOption(new Option("--api-key <value>", "Refused: keys are never accepted on the command line").hideHelp());
}

function registerAdd(program: Command, endpoint: Command): void {
  addSaveOptions(endpoint.command("add"))
    .description("Save a new OpenAI-compatible endpoint (saving does not connect)")
    .action(async (opts: EndpointFlagOptions) => {
      let fields: SaveFields;
      let body: Record<string, unknown>;
      try {
        fields = await parseSaveFields(opts);
        body = addBody(fields);
      } catch (error) {
        reportInputError(program, error);
        return;
      }
      loopbackNote(fields);
      const device = await requireDevice(program);
      if (!device) return;
      await call(program, device, { method: "ai-endpoint-save", body, timeoutMs: PROBE_TIMEOUT_MS, secrets: secretsOf(fields) });
    });
}

function registerEdit(program: Command, endpoint: Command): void {
  addSaveOptions(endpoint.command("edit <endpoint>"))
    .description("Change a saved endpoint; omitted flags keep their saved values")
    .option("--clear-api-key", "Remove the stored API key")
    .action(async (ref: string, opts: EndpointFlagOptions) => {
      let fields: SaveFields;
      try {
        fields = await parseSaveFields(opts);
      } catch (error) {
        reportInputError(program, error);
        return;
      }
      loopbackNote(fields);
      await withEndpoint(program, ref, (existing) => ({
        method: "ai-endpoint-save",
        body: editBody(existing, fields),
        timeoutMs: PROBE_TIMEOUT_MS,
        secrets: secretsOf(fields),
      }));
    });
}

function registerReadCommands(program: Command, endpoint: Command): void {
  endpoint.command("list")
    .description("List saved endpoints, the active selection and what localhost means on the device")
    .action(async () => {
      const device = await requireDevice(program);
      if (!device) return;
      await call(program, device, { method: "ai-endpoints", body: {}, timeoutMs: PROBE_TIMEOUT_MS });
    });

  endpoint.command("models <endpoint>")
    .description("Refresh and list the models the endpoint serves (GET {base}/models on the device)")
    .action(async (ref: string) => {
      await withEndpoint(program, ref, (found) => ({ method: "ai-endpoint-models", body: { id: found.id }, timeoutMs: PROBE_TIMEOUT_MS }));
    });

  endpoint.command("health [endpoint]")
    .description("Show endpoint health (default: the active endpoint)")
    .option("--refresh", "Probe now instead of returning the cached state")
    .action(async (ref: string | undefined, opts: { refresh?: boolean }) => {
      const refresh = opts.refresh === true;
      if (ref === undefined) {
        const device = await requireDevice(program);
        if (!device) return;
        await call(program, device, { method: "ai-endpoint-health", body: { refresh }, timeoutMs: PROBE_TIMEOUT_MS });
        return;
      }
      await withEndpoint(program, ref, (found) => ({ method: "ai-endpoint-health", body: { id: found.id, refresh }, timeoutMs: PROBE_TIMEOUT_MS }));
    });
}

function registerActionCommands(program: Command, endpoint: Command): void {
  endpoint.command("remove <endpoint>")
    .description("Delete a saved endpoint and its stored API key (unloads it if active)")
    .action(async (ref: string) => {
      await withEndpoint(program, ref, (found) => ({ method: "ai-endpoint-remove", body: { id: found.id }, timeoutMs: PROBE_TIMEOUT_MS }));
    });

  endpoint.command("test <endpoint>")
    .description("Probe the endpoint, list models and run a short generation test")
    .option("--model <id>", "Model to test instead of the endpoint's selected model")
    .option("--no-generate", "Only probe reachability and model discovery")
    .option("--tools", "Also verify tool calling (records toolCalling with source 'test')")
    .action(async (ref: string, opts: { model?: string; generate: boolean; tools?: boolean }) => {
      const tools = opts.tools === true;
      await withEndpoint(program, ref, (found) => ({
        method: "ai-endpoint-test",
        body: { id: found.id, ...(opts.model ? { model: opts.model } : {}), generate: opts.generate, tools },
        timeoutMs: opts.generate || tools ? GENERATION_TEST_TIMEOUT_MS : PROBE_TIMEOUT_MS,
      }));
    });

  endpoint.command("use <endpoint>")
    .description("Make this endpoint (and optionally a model) the active AI backend; fails instead of falling back")
    .option("--model <id>", "Model ID to select, exactly as the server lists it")
    .action(async (ref: string, opts: { model?: string }) => {
      const device = await requireDevice(program);
      if (!device) return;
      const body: Record<string, unknown> = { backend: "openai", endpoint: ref };
      if (opts.model) body.model = opts.model;
      await call(program, device, { method: "ai-load", body, timeoutMs: LOAD_TIMEOUT_MS });
    });
}

export function registerAIEndpoint(program: Command, ai: Command): void {
  const endpoint = ai.command("endpoint")
    .description("Manage OpenAI-compatible inference endpoints (llama-server, LM Studio, vLLM, Ollama /v1, …) on a device");
  registerReadCommands(program, endpoint);
  registerAdd(program, endpoint);
  registerEdit(program, endpoint);
  registerActionCommands(program, endpoint);
}
