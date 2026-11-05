import { afterEach, describe, expect, it, vi } from "vitest";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createMcpServer } from "../../src/mcp/server.js";
import { createScriptMcpBody, redactScriptResult } from "../../src/mcp/script-tools.js";
import type { DiscoveredDevice } from "../../src/types.js";
const io = vi.hoisted(() => ({ ordinary: vi.fn(), pinned: vi.fn(), pin: vi.fn() }));
vi.mock("../../src/client/http-client.js", () => ({ sendCommand: io.ordinary, createPinnedCommandTransport: io.pin }));
const target: DiscoveredDevice = { id: "one", name: "one", ip: "127.0.0.1", port: 8420, platform: "windows", model: "CEF", width: 800, height: 600, version: "test", lastSeen: 0 };
const request = (reference: string): Record<string, unknown> => ({
  version: 1, tabId: "tab", actions: [{ action: "fill", target: { label: "Password" }, text: { secret: reference } }],
});
afterEach(() => { vi.clearAllMocks(); vi.unstubAllEnvs(); });
describe("operator-owned workflow secret references", () => {
  it("captures only configured environment values at launch and refuses model ENV selection", () => {
    const env = { ALLOWED_ENV: "initial-value" };
    Object.defineProperty(env, "FORBIDDEN_ENV", { get: () => { throw new Error("Forbidden ENV read"); } });
    const body = createScriptMcpBody('{"allowed":"ALLOWED_ENV"}', env);
    env.ALLOWED_ENV = "rotated-after-launch";
    expect(body(request("allowed"))).toMatchObject({ actions: [{ text: "initial-value", sensitive: true }] });
    expect(() => body(request("unlisted"))).toThrow("Invalid workflow or unavailable input/secret");
    expect(() => body({ ...request("unlisted"), secretEnv: { unlisted: "FORBIDDEN_ENV" } })).toThrow("Model environment selection is unavailable");
  });
  it.each(["not-json", "[]", '{"ref":"MISSING_ENV"}'])("uses fixed startup errors for invalid mapping", raw => {
    expect(() => createScriptMcpBody(raw, {})).toThrow("Invalid workflow secret reference configuration");
  });
  it("rejects unlisted refs and model ENV mappings through the actual MCP extension doorway before renderer calls", async () => {
    vi.stubEnv("KELPIE_WORKFLOW_SECRET_REFS", '{"allowed":"WORKFLOW_ALLOWED_ENV"}');
    vi.stubEnv("WORKFLOW_ALLOWED_ENV", "fixture-allowed-value");
    vi.stubEnv("WORKFLOW_FORBIDDEN_ENV", "fixture-unlisted-value");
    io.ordinary.mockResolvedValue({ ok: true, status: 200, data: { success: true } });
    io.pin.mockResolvedValue(io.pinned);
    io.pinned.mockImplementation(async (method: string) => ({ ok: true, status: 200, data: method === "getScriptStatus" ? { success: true, supportedVersions: [1] } : { success: true, output: "fixture-allowed-value" } }));
    const server = createMcpServer(target, new Set(["kelpie_play_script"]));
    const [clientSide, serverSide] = InMemoryTransport.createLinkedPair();
    const client = new Client({ name: "secret-ref-test", version: "test" });
    await server.connect(serverSide);
    await client.connect(clientSide);
    try {
      for (const args of [request("unlisted"), { ...request("unlisted"), secretEnv: { unlisted: "WORKFLOW_FORBIDDEN_ENV" } }]) {
        const result = await client.callTool({ name: "kelpie_extension", arguments: { name: "kelpie_play_script", arguments: args } });
        expect(result.isError).toBe(true);
      }
      expect(io.ordinary).not.toHaveBeenCalled();
      expect(io.pinned).not.toHaveBeenCalled();
      const allowed = await client.callTool({ name: "kelpie_extension", arguments: { name: "kelpie_play_script", arguments: request("allowed") } });
      expect(allowed.isError).not.toBe(true);
      expect(io.pinned).toHaveBeenCalledTimes(2);
      expect(JSON.stringify(allowed)).not.toContain("fixture-allowed-value");
      expect(JSON.stringify(allowed)).not.toContain("fixture-unlisted-value");
    } finally { await client.close(); await server.close(); }
  });
});

it("preserves trusted metadata while redacting dynamic output names and error/page content", () => {
  vi.stubEnv("WORKFLOW_ALLOWED_ENV", "error");
  const bind = createScriptMcpBody('{"allowed":"WORKFLOW_ALLOWED_ENV"}');
  const body = bind(request("allowed"));
  const result = redactScriptResult({
    success: true, runId: "run-error", status: "error",
    error: { code: "error", message: "page error reflected" },
    artifacts: [{ id: "error-artifact", mimeType: "image/png", byteLength: 4, sha256: "a".repeat(64), width: 1, height: 1, partial: false }],
    outputs: { error: "user error", nested: { error: "page error" } },
  }, body) as { success: boolean; runId: string; status: string; error: { code: string; message: string }; artifacts: { id: string }[]; outputs: Record<string, unknown> };
  expect(result.success).toBe(true);
  expect(result.runId).toBe("run-error");
  expect(result.status).toBe("error");
  expect(result.error.code).toBe("error");
  expect(result.error.message).toBe("page [REDACTED] reflected");
  expect(result.artifacts[0]?.id).toBe("error-artifact");
  expect(result.outputs).not.toHaveProperty("error");
  expect(result.outputs["[REDACTED]"]).toBe("user [REDACTED]");
  expect(result.outputs.nested).toEqual({ "[REDACTED]": "page [REDACTED]" });
});

it("scrubs only payload strings inside canonical extraction outputs", () => {
  vi.stubEnv("WORKFLOW_ALLOWED_ENV", "id");
  const bind = createScriptMcpBody('{"allowed":"WORKFLOW_ALLOWED_ENV"}');
  const body = bind({ ...request("allowed"), actions: [
    ...(request("allowed").actions as unknown[]),
    { action: "extract", name: "cards", params: { fields: [{ name: "id", selector: ".id", source: "text" }] } },
  ] });
  const result = redactScriptResult({ runId: "id-run", outputs: { cards: {
    url: "https://fixture/id", documentRevision: { availability: "unavailable" }, truncated: false,
    fields: [{ name: "id", status: "ok", values: ["id"], provenance: { selector: ".id", source: "text", matches: 1 } }],
    metadata: [{ key: "id", value: "id", selector: ".id", attribute: "content", authority: "publisher-claim" }],
    hash: "id",
  } } }, body);
  expect(result).toMatchObject({ runId: "id-run", outputs: { cards: {
    url: "https://fixture/[REDACTED]", documentRevision: { availability: "unavailable" }, truncated: false,
    fields: [{ name: "[REDACTED]", status: "ok", values: ["[REDACTED]"], provenance: { selector: ".[REDACTED]", source: "text", matches: 1 } }],
    metadata: [{ value: "[REDACTED]", authority: "publisher-claim" }], hash: "[REDACTED]",
  } } });
});

it("does not corrupt MIME/hash/protocol fields for a one-character secret", () => {
  vi.stubEnv("WORKFLOW_ALLOWED_ENV", "a");
  const body = createScriptMcpBody('{"allowed":"WORKFLOW_ALLOWED_ENV"}')(request("allowed"));
  expect(redactScriptResult({ success: true, runId: "a", artifacts: [{ id: "a", mimeType: "image/png", sha256: "a".repeat(64), byteLength: 1 }], outputs: { a: "a" } }, body)).toMatchObject({
    success: true, runId: "a", artifacts: [{ id: "a", mimeType: "image/png", sha256: "a".repeat(64), byteLength: 1 }],
    outputs: { "[REDACTED]": "[REDACTED]" },
  });
});

it("redacts URL-encoded page reflections without changing trusted IDs", () => {
  vi.stubEnv("WORKFLOW_ALLOWED_ENV", "a b+!");
  const body = createScriptMcpBody('{"allowed":"WORKFLOW_ALLOWED_ENV"}')(request("allowed"));
  expect(redactScriptResult({ runId: "opaque-a b+!", outputs: { url: "https://fixture/?value=" + encodeURIComponent("a b+!") } }, body)).toMatchObject({
    runId: "opaque-a b+!", outputs: { url: "https://fixture/?value=[REDACTED]" },
  });
});

it("refuses redacted output-name collisions without losing trusted run metadata", () => {
  vi.stubEnv("WORKFLOW_FIRST", "run");
  vi.stubEnv("WORKFLOW_SECOND", "error");
  const bind = createScriptMcpBody('{"first":"WORKFLOW_FIRST","second":"WORKFLOW_SECOND"}');
  const body = bind({ version: 1, tabId: "tab", actions: [
    { action: "fill", target: { label: "First" }, text: { secret: "first" } },
    { action: "fill", target: { label: "Second" }, text: { secret: "second" } },
  ] });
  expect(redactScriptResult({ success: true, runId: "run-error", actionsExecuted: 2, outputs: { run: "one", error: "two" } }, body)).toEqual({
    success: false, mayHaveCompleted: true, runId: "run-error", actionsExecuted: 2,
    error: { code: "OUTPUT_REDACTION_COLLISION", message: "Workflow output cannot be returned safely" },
  });
});

it("matches overlapping secrets once and does not rescan producer markers", () => {
  vi.stubEnv("WORKFLOW_FIRST", "e");
  vi.stubEnv("WORKFLOW_SECOND", "redacted");
  const body = createScriptMcpBody('{"first":"WORKFLOW_FIRST","second":"WORKFLOW_SECOND"}')({ version: 1, tabId: "tab", actions: [
    { action: "fill", target: { label: "First" }, text: { secret: "first" } },
    { action: "fill", target: { label: "Second" }, text: { secret: "second" } },
  ] });
  expect(redactScriptResult({ outputs: { result: "redacted e [redacted]" } }, body)).toMatchObject({
    outputs: { "r[REDACTED]sult": "[REDACTED] [REDACTED] [REDACTED]" },
  });
});

it("refuses oversized sensitive output with a fixed post-execution error", () => {
  vi.stubEnv("WORKFLOW_ALLOWED_ENV", "secret");
  const body = createScriptMcpBody('{"allowed":"WORKFLOW_ALLOWED_ENV"}')(request("allowed"));
  expect(redactScriptResult({ runId: "opaque", outputs: { large: "x".repeat(262145) } }, body)).toEqual({
    success: false, mayHaveCompleted: true, runId: "opaque",
    error: { code: "OUTPUT_REDACTION_LIMIT", message: "Workflow output cannot be returned safely" },
  });
});


it("redacts mixed-case percent hex without folding ordinary secret text", () => {
  const body = createScriptMcpBody('{"allowed":"WORKFLOW_ALLOWED_ENV"}', { WORKFLOW_ALLOWED_ENV: "Aa b+!" })(request("allowed"));
  expect(redactScriptResult({ outputs: {
    lowerUri: "Aa%20b%2b!", mixedForm: "Aa+b%2b%21", upperUri: "Aa%20b%2B!",
    differentPlainCase: "aa b+!", differentEncodedPlainCase: "Aa%20B%2b!",
  } }, body)).toMatchObject({ outputs: {
    lowerUri: "[REDACTED]", mixedForm: "[REDACTED]", upperUri: "[REDACTED]",
    differentPlainCase: "aa b+!", differentEncodedPlainCase: "Aa%20B%2b!",
  } });
  const literal = createScriptMcpBody('{"allowed":"WORKFLOW_ALLOWED_ENV"}', { WORKFLOW_ALLOWED_ENV: "token%2FValue" })(request("allowed"));
  expect(redactScriptResult({ outputs: { raw: "token%2FValue", different: "token%2fValue", encoded: "token%252FValue" } }, literal)).toMatchObject({
    outputs: { raw: "[REDACTED]", different: "token%2fValue", encoded: "[REDACTED]" },
  });
});
