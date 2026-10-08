import { Readable } from "node:stream";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { addDevice, clearDevices } from "../../src/discovery/registry.js";
import { createProgram } from "../../src/program.js";
import { askBody } from "../../src/commands/ai.js";
import {
  EndpointInputError,
  addBody,
  editBody,
  findEndpoint,
  parseSaveFields,
} from "../../src/commands/ai-endpoint-input.js";
import type { DiscoveredDevice } from "../../src/types.js";

const device: DiscoveredDevice = {
  id: "endpoint-test-device",
  name: "Endpoint Test Mac",
  ip: "192.168.1.77",
  port: 8420,
  platform: "macos",
  model: "Mac",
  width: 0,
  height: 0,
  version: "1.0.0",
  lastSeen: Date.now(),
};

const KEY = "sk-endpoint-test-abcdef123456";

const saved = [
  { id: "e-1", name: "Strata (tunnel)", baseURL: "http://127.0.0.1:18880/v1", model: "qwen3", hasApiKey: true },
  { id: "e-2", name: "Studio", baseURL: "http://studio.local:1234/v1", model: null, hasApiKey: false },
];

interface Call { method: string; body: Record<string, unknown> | undefined; signal: AbortSignal | undefined }

let calls: Call[] = [];
let logs: string[] = [];
let replies: Record<string, unknown> = {};

function installFetch(): void {
  globalThis.fetch = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
    const method = String(url).split("/v1/")[1] ?? "";
    const body = init?.body ? JSON.parse(init.body as string) as Record<string, unknown> : undefined;
    calls.push({ method, body, signal: init?.signal ?? undefined });
    const reply = replies[method] ?? (method === "ai-endpoints" ? { success: true, endpoints: saved } : { success: true });
    return new Response(JSON.stringify(reply), { status: 200, headers: { "Content-Type": "application/json" } });
  }) as typeof fetch;
}

const run = (...args: string[]) =>
  createProgram("0.0.0-test").parseAsync(["node", "kelpie", "--device", device.id, ...args]);

function lastBody(method: string): Record<string, unknown> | undefined {
  return [...calls].reverse().find((call) => call.method === method)?.body;
}

function printed(): string {
  return logs.join("\n");
}

describe("kelpie ai endpoint — request mapping", () => {
  const originalFetch = globalThis.fetch;

  beforeEach(() => {
    calls = [];
    logs = [];
    replies = {};
    installFetch();
    addDevice(device);
    vi.spyOn(console, "log").mockImplementation((line: string) => { logs.push(line); });
    vi.spyOn(process.stderr, "write").mockImplementation(() => true);
    process.exitCode = undefined;
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
    clearDevices();
    vi.restoreAllMocks();
    delete process.env.KELPIE_TEST_ENDPOINT_KEY;
    process.exitCode = undefined;
  });

  it("list sends ai-endpoints", async () => {
    await run("ai", "endpoint", "list");
    expect(calls.map((call) => call.method)).toEqual(["ai-endpoints"]);
  });

  it("add maps flags, normalises the URL and reads the key from an env var", async () => {
    process.env.KELPIE_TEST_ENDPOINT_KEY = KEY;
    await run(
      "ai", "endpoint", "add", "--name", "Studio", "--base-url", "http://Studio.local:1234/v1/chat/completions",
      "--model", "qwen3-8b", "--context-window", "32768", "--vision", "no", "--tool-calling", "yes",
      "--json-schema", "unknown", "--api-key-env", "KELPIE_TEST_ENDPOINT_KEY",
    );
    expect(lastBody("ai-endpoint-save")).toEqual({
      name: "Studio",
      baseURL: "http://studio.local:1234/v1",
      apiKey: KEY,
      model: "qwen3-8b",
      capabilities: { contextWindow: 32768, vision: false, toolCalling: true, jsonSchema: null },
    });
    expect(process.exitCode).toBeUndefined();
  });

  it("never prints the API key, even when the device echoes it", async () => {
    process.env.KELPIE_TEST_ENDPOINT_KEY = KEY;
    replies["ai-endpoint-save"] = { success: false, error: { code: "ENDPOINT_ERROR", message: `bad key ${KEY}` }, apiKey: KEY };
    await run("ai", "endpoint", "add", "--name", "S", "--base-url", "http://h:1/v1", "--api-key-env", "KELPIE_TEST_ENDPOINT_KEY");
    expect(printed()).not.toContain(KEY);
    expect(printed()).toContain("[REDACTED]");
  });

  it("refuses a literal --api-key without contacting the device or echoing it", async () => {
    await run("ai", "endpoint", "add", "--name", "S", "--base-url", "http://h:1/v1", `--api-key=${KEY}`);
    expect(calls).toEqual([]);
    expect(printed()).toContain("API_KEY_ON_COMMAND_LINE");
    expect(printed()).not.toContain(KEY);
    expect(process.exitCode).toBe(1);
  });

  it("rejects an invalid base URL before contacting the device", async () => {
    await run("ai", "endpoint", "add", "--name", "S", "--base-url", "http://user:pw@h:1/v1");
    expect(calls).toEqual([]);
    expect(printed()).toContain("INVALID_ENDPOINT_URL");
    expect(process.exitCode).toBe(1);
  });

  it("edit resolves a name, carries saved fields over and can clear the key", async () => {
    await run("ai", "endpoint", "edit", "strata (tunnel)", "--clear-api-key", "--vision", "unknown");
    expect(lastBody("ai-endpoint-save")).toEqual({
      id: "e-1",
      name: "Strata (tunnel)",
      baseURL: "http://127.0.0.1:18880/v1",
      clearApiKey: true,
      model: "qwen3",
      capabilities: { vision: null },
    });
  });

  it("edit replaces the URL and context window when given", async () => {
    await run("ai", "endpoint", "edit", "e-2", "--base-url", "http://10.0.0.9:8080", "--context-window", "unset");
    expect(lastBody("ai-endpoint-save")).toEqual({
      id: "e-2", name: "Studio", baseURL: "http://10.0.0.9:8080/v1", capabilities: { contextWindow: null },
    });
  });

  it("an unknown endpoint fails with ENDPOINT_NOT_FOUND and sends nothing else", async () => {
    await run("ai", "endpoint", "remove", "nope");
    expect(calls.map((call) => call.method)).toEqual(["ai-endpoints"]);
    expect(printed()).toContain("ENDPOINT_NOT_FOUND");
    expect(process.exitCode).toBe(1);
  });

  it.each([
    [["remove", "Studio"], "ai-endpoint-remove", { id: "e-2" }],
    [["models", "e-1"], "ai-endpoint-models", { id: "e-1" }],
    [["test", "Studio"], "ai-endpoint-test", { id: "e-2", generate: true, tools: false }],
    [["test", "Studio", "--no-generate", "--tools", "--model", "m2"], "ai-endpoint-test", { id: "e-2", model: "m2", generate: false, tools: true }],
    [["health", "Studio", "--refresh"], "ai-endpoint-health", { id: "e-2", refresh: true }],
  ])("%j sends %s", async (args, method, body) => {
    await run("ai", "endpoint", ...args);
    expect(lastBody(method)).toEqual(body);
  });

  it("health without an endpoint asks for the active one", async () => {
    await run("ai", "endpoint", "health");
    expect(calls).toEqual([expect.objectContaining({ method: "ai-endpoint-health", body: { refresh: false } })]);
  });

  it("use sends ai-load with backend openai, unresolved", async () => {
    await run("ai", "endpoint", "use", "Studio", "--model", "qwen3-8b");
    expect(calls.map((call) => call.method)).toEqual(["ai-load"]);
    expect(lastBody("ai-load")).toEqual({ backend: "openai", endpoint: "Studio", model: "qwen3-8b" });
  });

  it("ai load keeps sending plain model IDs", async () => {
    await run("ai", "load", "gemma-4-e2b-q4");
    expect(lastBody("ai-load")).toEqual({ model: "gemma-4-e2b-q4" });
  });

  it("ai cancel sends ai-cancel", async () => {
    await run("ai", "cancel");
    expect(calls.map((call) => call.method)).toEqual(["ai-cancel"]);
  });

  it("ai ask forwards agent flags", async () => {
    await run("ai", "ask", "what is on the page?", "--agent", "--allow-actions", "--max-steps", "5");
    expect(lastBody("ai-infer")).toEqual({
      prompt: "what is on the page?", maxTokens: 512, temperature: 0.7, agent: true, allowActions: true, maxSteps: 5,
    });
  });

  it("ai ask --no-agent sends agent false and omits unset agent fields", async () => {
    await run("ai", "ask", "hi", "--no-agent");
    expect(lastBody("ai-infer")).toEqual({ prompt: "hi", maxTokens: 512, temperature: 0.7, agent: false });
    await run("ai", "ask", "hi", "-c", "page_text");
    expect(lastBody("ai-infer")).toEqual({ prompt: "hi", context: "page_text", maxTokens: 512, temperature: 0.7 });
  });
});

describe("endpoint flag parsing", () => {
  it("reads the key from stdin", async () => {
    const fields = await parseSaveFields({ name: "S", baseUrl: "http://h:1", apiKeyStdin: true }, Readable.from([`${KEY}\n`]));
    expect(addBody(fields)).toEqual({ name: "S", baseURL: "http://h:1/v1", apiKey: KEY });
  });

  it.each([
    [{ apiKeyEnv: "A", apiKeyStdin: true }, /only one of/],
    [{ apiKeyEnv: "A", clearApiKey: true }, /only one of/],
    [{ apiKeyEnv: "MISSING_VAR_FOR_TEST" }, /not set/],
    [{ vision: "maybe" }, /--vision must be yes, no or unknown/],
    [{ contextWindow: "0" }, /--context-window/],
    [{ contextWindow: "12k" }, /--context-window/],
    [{ name: "  " }, /--name must not be empty/],
  ])("rejects %j", async (opts, message) => {
    await expect(parseSaveFields(opts, Readable.from([]), {})).rejects.toThrow(message);
  });

  it("add requires a name and base URL and refuses --clear-api-key", () => {
    expect(() => addBody({ baseURL: "http://h/v1" })).toThrow(EndpointInputError);
    expect(() => addBody({ name: "S" })).toThrow(/--base-url is required/);
    expect(() => addBody({ name: "S", baseURL: "http://h/v1", clearApiKey: true })).toThrow(/only applies to edit/);
  });

  it("edit keeps an explicit empty model out of the body", () => {
    expect(editBody({ id: "e", name: "n", baseURL: "http://h/v1", model: null }, { model: "" })).toEqual({ id: "e", name: "n", baseURL: "http://h/v1" });
  });

  it("finds endpoints by id, exact name, then unique case-insensitive name", () => {
    const list = [{ id: "a", name: "Studio" }, { id: "b", name: "studio" }, { id: "c", name: "Box" }];
    expect(findEndpoint(list, "c")?.id).toBe("c");
    expect(findEndpoint(list, "studio")?.id).toBe("b");
    expect(findEndpoint(list, "STUDIO")).toBeUndefined();
    expect(findEndpoint(list, "box")?.id).toBe("c");
  });

  it("askBody validates max steps and refuses allow-actions without the agent", () => {
    expect(() => askBody("p", { maxSteps: "41" })).toThrow(/1 to 40/);
    expect(() => askBody("p", { maxSteps: "0" })).toThrow(/1 to 40/);
    expect(() => askBody("p", { agent: false, allowActions: true })).toThrow(/needs the agent/);
  });
});
