import { sendCommand, createPinnedCommandTransport, type HttpResponse, type PinnedCommandTransport } from "../client/http-client.js";
import type { DiscoveredDevice } from "../types.js";
import { bindScriptInputs } from "@unlikeotherai/kelpie-shared";
import { ToolInputError } from "./ai-endpoint-tools.js";

const boundSecrets = new WeakMap<Record<string, unknown>, string[]>();

function bindHostScript(args: Record<string, unknown>, resolveSecret: (reference: string) => string | undefined): Record<string, unknown> {
  const { device: _device, values, secretEnv: _secretEnv, ...script } = args;
  if (script.version === undefined) {
    if (values !== undefined || ["capture", "pointer", "tapIndicator", "inputs", "sessionId"].some(key => script[key] !== undefined)) throw new ToolInputError("INVALID_SCRIPT", "Workflow bindings and capture require script version 1");
    return script;
  }
  try {
    const secrets: string[] = [];
    const body = bindScriptInputs(script, values as Record<string, unknown> | undefined, reference => {
      const value = resolveSecret(reference);
      if (value) secrets.push(value);
      return value;
    }) as unknown as Record<string, unknown>;
    if (Array.isArray(body.actions)) for (const raw of body.actions) {
      const action = raw as Record<string, unknown>;
      if (action.sensitive === true && typeof action.text === "string" && action.text.length) secrets.push(action.text);
    }
    boundSecrets.set(body, [...new Set(secrets)]);
    return body;
  } catch {
    throw new ToolInputError("INVALID_SCRIPT", "Invalid workflow or unavailable input/secret");
  }
}

/** Only trusted CLI argv supplies ENV names. They never travel to the device. */
export function scriptHostBody(args: Record<string, unknown>): Record<string, unknown> {
  if (args.secretEnv !== undefined && args.version !== 1) throw new ToolInputError("INVALID_SCRIPT", "Workflow bindings require script version 1");
  const references = args.secretEnv as Record<string, unknown> | undefined;
  return bindHostScript(args, reference => {
    if (!references || !Object.hasOwn(references, reference)) return undefined;
    const name = references[reference];
    if (typeof name !== "string" || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) return undefined;
    const value = process.env[name];
    return typeof value === "string" ? value : undefined;
  });
}

/** Capture an operator-owned allowlist and its values once for this MCP launch. No model setter exists. */
export function createScriptMcpBody(raw?: string, env: NodeJS.ProcessEnv = process.env): (args: Record<string, unknown>) => Record<string, unknown> {
  const configured = new Map<string, string>();
  try {
    if (raw) {
      if (raw.length > 16_384) throw new Error();
      const mapping: unknown = JSON.parse(raw);
      if (!mapping || typeof mapping !== "object" || Array.isArray(mapping)) throw new Error();
      const entries = Object.entries(mapping);
      if (entries.length > 128) throw new Error();
      for (const [reference, name] of entries) {
        if (!reference.length || reference.length > 128 || typeof name !== "string" || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) throw new Error();
        if (!Object.hasOwn(env, name)) throw new Error();
        const value = env[name];
        if (typeof value !== "string") throw new Error();
        configured.set(reference, value);
      }
    }
  } catch { throw new Error("Invalid workflow secret reference configuration"); }
  return args => {
    if (Object.hasOwn(args, "secretEnv")) throw new ToolInputError("INVALID_SCRIPT", "Model environment selection is unavailable");
    return bindHostScript(args, reference => configured.get(reference));
  };
}

/** Preserve trusted control metadata; redact page/error payloads and dynamic names by typed path. */
export function redactScriptResult(value: unknown, body: Record<string, unknown>): unknown {
  const secrets = boundSecrets.get(body) ?? [];
  if (!secrets.length) return value;
  const patterns = [...new Set(secrets.flatMap(secret => {
    try { return [secret, encodeURIComponent(secret), new URLSearchParams({ v: secret }).toString().slice(2)]; }
    catch { return [secret]; }
  }))];
  const limit = new Error("OUTPUT_REDACTION_LIMIT");
  const collision = new Error("OUTPUT_REDACTION_COLLISION");
  patterns.sort((a, b) => b.length - a.length);
  let comparisons = 0, bytes = 0;
  const mask = (text: string): string => {
    if (Buffer.byteLength(text) > 262144) throw limit;
    const chunks: string[] = [];
    let length = 0;
    for (let index = 0; index < text.length;) {
      // Producer redaction markers are fixed protocol literals, not newly exposed page content.
      if (text.slice(index, index + 10).toLowerCase() === "[redacted]") {
        chunks.push("[REDACTED]"); length += 10; index += 10;
      } else {
        let matched = false;
        for (const pattern of patterns) {
          if (++comparisons > 8000000) throw limit;
          if (!pattern.length || pattern.length > text.length - index) continue;
          let same = true;
          for (let offset = 0; offset < pattern.length; offset++) {
            if (++comparisons > 8000000) throw limit;
            if (text[index + offset] !== pattern[offset]) { same = false; break; }
          }
          if (same) { chunks.push("[REDACTED]"); length += 10; index += pattern.length; matched = true; break; }
        }
        if (!matched) { chunks.push(text[index] ?? ""); length++; index++; }
      }
      if (length > 262144) throw limit;
    }
    const output = chunks.join("");
    bytes += Buffer.byteLength(output);
    if (bytes > 262144) throw limit;
    return output;
  };
  let nodes = 0, depth = 0;
  const bounded = (run: () => unknown): unknown => {
    if (++nodes > 10000 || depth >= 64) throw limit;
    depth++;
    try { return run(); } finally { depth--; }
  };
  type Scrub = (value: unknown) => unknown;
  const array = (input: unknown, scrub: Scrub): unknown => bounded(() => {
    if (!Array.isArray(input)) return dynamic(input);
    const output: unknown[] = [];
    for (const item of input) {
      if (++nodes > 10000) throw limit;
      output.push(scrub(item));
    }
    return output;
  });
  const object = (input: unknown, rules: Record<string, Scrub>): unknown => bounded(() => {
    if (!input || typeof input !== "object" || Array.isArray(input)) return dynamic(input);
    const output = Object.create(null) as Record<string, unknown>;
    for (const key in input) {
      if (!Object.hasOwn(input, key)) continue;
      if (++nodes > 10000) throw limit;
      const scrub = Object.hasOwn(rules, key) ? rules[key] : undefined;
      const renamed = scrub ? key : mask(key);
      const item: unknown = (input as Record<string, unknown>)[key];
      if (Object.hasOwn(output, renamed)) throw collision;
      output[renamed] = scrub ? scrub(item) : dynamic(item);
    }
    return output;
  });
  const dynamic: Scrub = input => {
    if (typeof input === "string") return mask(input);
    if (Array.isArray(input)) return array(input, dynamic);
    return input && typeof input === "object" ? object(input, {}) : input;
  };
  const scalar: Scrub = input => input && typeof input === "object" ? dynamic(input) : input;
  const dimensions: Scrub = input => object(input, { x: scalar, y: scalar, width: scalar, height: scalar });
  const error: Scrub = input => object(input, { code: scalar, message: dynamic, mayHaveCompleted: scalar });
  const issue: Scrub = input => object(input, { index: scalar, action: scalar, error, code: scalar, message: dynamic, skipped: scalar, mayHaveCompleted: scalar });
  const artifact: Scrub = input => object(input, {
    id: scalar, artifactId: scalar, runId: scalar, mimeType: scalar, byteLength: scalar, sha256: scalar,
    partial: scalar, width: scalar, height: scalar, durationMs: scalar, frameCount: scalar, droppedFrames: scalar,
    viewport: dimensions, documentId: scalar, actionIndex: scalar,
  });
  const field: Scrub = input => object(input, {
    name: dynamic, status: scalar, values: input => array(input, dynamic),
    records: input => array(input, input => array(input, field)),
    provenance: input => object(input, { selector: dynamic, source: scalar, matches: scalar, matchesLimited: scalar }),
  });
  const extraction: Scrub = input => object(input, {
    url: dynamic, documentRevision: input => object(input, { availability: scalar }),
    fields: input => array(input, field), truncated: scalar,
    metadata: input => array(input, input => object(input, { key: dynamic, value: dynamic, selector: dynamic, attribute: dynamic, authority: scalar })),
  });
  const extractNames = new Set<string>();
  const statusNames = new Set<string>();
  if (Array.isArray(body.actions)) for (const raw of body.actions) {
    const step = raw as Record<string, unknown>;
    if (step.action === "extract" && typeof step.name === "string") extractNames.add(step.name);
    if (step.action === "output" && step.source === "status" && typeof step.name === "string") statusNames.add(step.name);
  }
  const outputs: Scrub = input => bounded(() => {
    if (!input || typeof input !== "object" || Array.isArray(input)) return dynamic(input);
    const output = Object.create(null) as Record<string, unknown>;
    for (const name in input) {
      if (!Object.hasOwn(input, name)) continue;
      if (++nodes > 10000) throw limit;
      const renamed = mask(name);
      const item: unknown = (input as Record<string, unknown>)[name];
      if (Object.hasOwn(output, renamed)) throw collision;
      output[renamed] = extractNames.has(name) ? extraction(item) : statusNames.has(name) && typeof item === "string" && ["loading", "interactive", "complete"].includes(item) ? item : dynamic(item);
    }
    return output;
  });
  try {
    return object(value, {
    version: scalar, success: scalar, runId: scalar, status: scalar, state: scalar, playing: scalar,
    currentAction: scalar, currentActionName: scalar, totalActions: scalar, actionsExecuted: scalar, actionsSucceeded: scalar,
    totalDurationMs: scalar, elapsedMs: scalar, abortRequested: scalar, aborted: scalar, partial: scalar,
    inputGuarantee: scalar, mayHaveCompleted: scalar, documentId: scalar, tabId: scalar,
    error, errors: input => array(input, issue), artifacts: input => array(input, artifact),
    screenshots: input => array(input, artifact), outputs,
    name: dynamic, url: dynamic, title: dynamic, message: dynamic, output: dynamic, value: dynamic, data: dynamic,
    });
  } catch (error) {
    if (error !== limit && error !== collision) throw error;
    const result = value && typeof value === "object" ? value as Record<string, unknown> : {};
    return {
      success: false, mayHaveCompleted: true,
      ...(typeof result.runId === "string" ? { runId: result.runId } : {}),
      ...(typeof result.actionsExecuted === "number" ? { actionsExecuted: result.actionsExecuted } : {}),
      error: { code: error === collision ? "OUTPUT_REDACTION_COLLISION" : "OUTPUT_REDACTION_LIMIT", message: "Workflow output cannot be returned safely" },
    };
  }
}

/** Read-only authorization precedes strict admission on one immutable grant/socket. */
export async function admitScriptTransport(device: DiscoveredDevice, version: unknown): Promise<
  { ok: true; send: PinnedCommandTransport } | { ok: false; response: HttpResponse }
> {
  if (version === undefined) return { ok: true, send: (method, body, timeout) => sendCommand(device, method, body, timeout) };
  const unsupported = (): { ok: false; response: HttpResponse } => ({ ok: false, response: {
    ok: false, status: 400, data: { success: false, error: { code: "UNSUPPORTED_SCRIPT_VERSION", message: "This browser must be updated to support script version 1" } },
  } });
  if (version !== 1) return unsupported();
  const authorized = await sendCommand(device, "getCapabilities", {}, 10000);
  if (!authorized.ok) return { ok: false, response: { ...authorized, data: { success: false, error: { code: "SCRIPT_AUTHORIZATION_FAILED", message: "Script authorization failed" } } } };
  const send = await createPinnedCommandTransport(device);
  const status = await send("getScriptStatus", {}, 10000);
  const data = status.data && typeof status.data === "object" ? status.data as Record<string, unknown> : {};
  const versions = data.supportedVersions;
  if (!status.ok || data.success !== true || !Array.isArray(versions) || versions.length > 32 ||
      versions.some(value => !Number.isSafeInteger(value) || (value as number) < 1) ||
      new Set(versions).size !== versions.length || !versions.includes(1)) return unsupported();
  return { ok: true, send };
}

/** Admit playback once; a lost response never retries an uncertain mutation. */
export async function sendScriptPlayback(device: DiscoveredDevice, body: Record<string, unknown>, timeout: number): Promise<HttpResponse> {
  const admission = await admitScriptTransport(device, body.version);
  if (!admission.ok) return admission.response;
  const result = await admission.send("playScript", body, timeout);
  if (result.status !== 0 && result.status !== 408) return result;
  return { ...result, data: { success: false, mayHaveCompleted: true, error: {
    code: "SCRIPT_COMPLETION_UNKNOWN", message: "Playback completion is unknown; inspect script status",
  } } };
}
