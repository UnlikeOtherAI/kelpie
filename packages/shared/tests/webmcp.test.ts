import { describe, expect, it, vi } from "vitest";
import { boundedWebMcpJson } from "../src/browser-control/webmcp-json.js";
import { webMcpCallParamsSchema, webMcpDiscoverParamsSchema } from "../src/browser-control/webmcp-schema.js";
import { createWebMcpController } from "../src/browser-control/webmcp.js";
import type { WebMcpPageInput } from "../src/browser-control/webmcp-reader.js";
import type { WebMcpBinding } from "../src/browser-control/webmcp.js";
import type { WebMcpIdentity } from "../src/browser-control/webmcp-schema.js";

const identity: WebMcpIdentity = { sessionId: "owned", origin: "https://fixture.example", documentGeneration: "doc1" };
const discovery = { available: true, origin: identity.origin, documentGeneration: identity.documentGeneration, untrusted: true, tools: [{ ref: "ref1", name: "mutates",
  description: "Untrusted instruction", annotations: { readOnlyHint: true } }], truncated: false };
const response = (value: unknown) => ({ ok: true, value });
function fixture() {
  const evaluate = vi.fn<(input: WebMcpPageInput) => Promise<unknown>>(async () => response(discovery));
  const authorize = vi.fn();
  const binding: WebMcpBinding = { inputEncoding: "object", identity: vi.fn(async () => ({ ...identity })), authorize, evaluate };
  return { evaluate, authorize, binding, controller: createWebMcpController(binding) };
}

describe("bounded WebMCP JSON", () => {
  const limits = { maxBytes: 1024, maxDepth: 3, maxProperties: 20 };
  it("copies plain data without invoking accessors or serialization hooks", () => {
    const getter = vi.fn();
    const value = Object.defineProperty({}, "secret", { enumerable: true, get: getter });
    expect(() => boundedWebMcpJson(value, limits)).toThrow(/data properties/);
    expect(getter).not.toHaveBeenCalled();
    const hook = vi.fn();
    expect(() => boundedWebMcpJson({ toJSON: hook }, limits)).toThrow();
    expect(hook).not.toHaveBeenCalled();
    expect(boundedWebMcpJson(JSON.parse('{"__proto__":{"owned":true}}'), limits)).toEqual(JSON.parse('{"__proto__":{"owned":true}}'));
    expect(({} as { owned?: boolean }).owned).toBeUndefined();
  });

  it("rejects cycles, deep nesting, sparse arrays, nonfinite numbers and output budgets", () => {
    const cycle: { self?: unknown } = {}; cycle.self = cycle;
    const sparse: unknown[] = []; sparse[1_000_000] = "x";
    for (const value of [cycle, { a: { b: { c: { d: 1 } } } }, sparse, { bad: Infinity }, { text: "x".repeat(1025) }]) {
      expect(() => boundedWebMcpJson(value, limits)).toThrow();
    }
    expect(() => boundedWebMcpJson({ x: 1, y: 2 }, { ...limits, maxProperties: 1 })).toThrow(/property/);
  });

  it("requires exact origins and bounded object input at the public schema", () => {
    for (const origin of ["https://fixture.example/path", "https://fixture.example/", "null", "file:///"]) {
      expect(webMcpDiscoverParamsSchema.safeParse({ origin }).success).toBe(false);
    }
    expect(webMcpCallParamsSchema.safeParse({ origin: identity.origin, ref: "x", input: [] }).success).toBe(false);
    expect(webMcpCallParamsSchema.safeParse({ origin: identity.origin, ref: "x", input: { x: "x".repeat(16_385) } }).success).toBe(false);
    expect(webMcpCallParamsSchema.safeParse({ origin: identity.origin, ref: "x", input: {}, endpoint: "https://foreign.example" }).success).toBe(false);
  });
});

describe("WebMCP host policy and completion ownership", () => {
  it("rejects unaudited encodings before browser invocation", () => {
    const f = fixture();
    expect(() => createWebMcpController({ ...f.binding, inputEncoding: "guess" as never })).toThrow(/audited/);
    expect(f.evaluate).not.toHaveBeenCalled();
  });
  it("checks exact origin and explicit discovery grant before executing browser code", async () => {
    const f = fixture();
    await expect(f.controller.discover({ origin: "https://foreign.example" })).rejects.toMatchObject({ code: "ACCESS_DENIED" });
    expect(f.evaluate).not.toHaveBeenCalled();
    f.authorize.mockImplementation(() => { throw new Error("not granted"); });
    await expect(f.controller.discover({ origin: identity.origin })).rejects.toThrow("not granted");
    expect(f.evaluate).not.toHaveBeenCalled();
  });

  it("authorizes every invocation as a call regardless of readOnlyHint", async () => {
    const f = fixture();
    await f.controller.discover({ origin: identity.origin });
    f.authorize.mockImplementation((_identity: WebMcpIdentity, operation: string) => {
      if (operation === "call") throw new Error("actions disabled");
    });
    await expect(f.controller.call({ origin: identity.origin, ref: "ref1" })).rejects.toThrow("actions disabled");
    expect(f.evaluate).toHaveBeenCalledOnce();
    expect(f.authorize).toHaveBeenLastCalledWith(identity, "call");
  });

  it("requires a current document observation and consumes it on each invocation", async () => {
    const f = fixture();
    await expect(f.controller.call({ origin: identity.origin, ref: "ref1" })).rejects.toMatchObject({ code: "STALE_REFERENCE" });
    await f.controller.discover({ origin: identity.origin });
    f.evaluate.mockResolvedValue(response({ output: "done", untrusted: true }));
    expect(await f.controller.call({ origin: identity.origin, ref: "ref1" })).toMatchObject({ output: "done" });
    await expect(f.controller.call({ origin: identity.origin, ref: "ref1" })).rejects.toMatchObject({ code: "STALE_REFERENCE" });
  });

  it("rejects changed document generations before invocation", async () => {
    const f = fixture();
    await f.controller.discover({ origin: identity.origin });
    vi.mocked(f.binding.identity).mockResolvedValue({ ...identity, documentGeneration: "doc2" });
    await expect(f.controller.call({ origin: identity.origin, ref: "ref1" })).rejects.toMatchObject({ code: "STALE_REFERENCE" });
    expect(f.evaluate).toHaveBeenCalledOnce();
  });

  it("retains BUSY after timeout until the actual late reply retires without retry", async () => {
    vi.useFakeTimers();
    const f = fixture();
    try {
      await f.controller.discover({ origin: identity.origin });
      let finish: (value: ReturnType<typeof response>) => void = () => undefined;
      f.evaluate.mockImplementation(() => new Promise(resolve => { finish = resolve; }));
      const call = f.controller.call({ origin: identity.origin, ref: "ref1", timeoutMs: 20 });
      const rejected = expect(call).rejects.toMatchObject({ code: "TIMEOUT", mayHaveCompleted: true });
      await vi.advanceTimersByTimeAsync(21);
      await rejected;
      await expect(f.controller.probe(identity.origin)).rejects.toMatchObject({ code: "BUSY" });
      expect(f.evaluate).toHaveBeenCalledTimes(2);
      finish(response({ output: "late" }));
      await vi.advanceTimersByTimeAsync(0); // Drain the actual reply ownership chain.
      f.evaluate.mockResolvedValue(response({ available: true }));
      expect(await f.controller.probe(identity.origin)).toEqual({ available: true });
    } finally { vi.useRealTimers(); }
  });

  it("does not trust malformed availability or leak site error text", async () => {
    const f = fixture();
    f.evaluate.mockResolvedValue(response({ available: "yes" }));
    await expect(f.controller.probe(identity.origin)).rejects.toMatchObject({ code: "WEBMCP_FAILED" });
    f.evaluate.mockResolvedValue({ ok: false, error: { code: "WEBMCP_FAILED", message: "SECRET_SITE_ERROR", mayHaveCompleted: false } } as never);
    const error = await f.controller.probe(identity.origin).catch((value: unknown) => value);
    expect(String(error)).not.toContain("SECRET_SITE_ERROR");
  });
});

describe("WebMCP admission and abort races", () => {
  it("does not dispatch after disposal races an awaited grant", async () => {
    const f = fixture();
    let signalEntered: () => void = () => undefined;
    const entered = new Promise<void>(resolve => { signalEntered = resolve; });
    let release: () => void = () => undefined;
    f.authorize.mockImplementationOnce(() => {
      signalEntered();
      return new Promise<void>(resolve => { release = resolve; });
    });
    const request = f.controller.probe(identity.origin);
    await entered;
    await f.controller.dispose();
    release();
    await expect(request).rejects.toMatchObject({ code: "SESSION_CLOSED", mayHaveCompleted: false });
    expect(f.evaluate.mock.calls.map(([input]) => input.operation)).toEqual(["dispose"]);
  });

  it("keeps abort rejection fenced until trusted actual document retirement", async () => {
    const f = fixture();
    const retired = vi.fn(async () => false);
    f.binding.isDocumentRetired = retired;
    await f.controller.discover({ origin: identity.origin });
    f.evaluate.mockResolvedValue({ ok: false, error: { code: "TIMEOUT", mayHaveCompleted: true }, completionUnknown: true });
    await expect(f.controller.call({ origin: identity.origin, ref: "ref1" })).rejects.toMatchObject({ code: "TIMEOUT", mayHaveCompleted: true });
    vi.mocked(f.binding.identity).mockResolvedValue({ ...identity, documentGeneration: "different-but-not-proof" });
    await expect(f.controller.probe(identity.origin)).rejects.toMatchObject({ code: "BUSY" });
    expect(retired).toHaveBeenCalledWith(identity);
    retired.mockResolvedValue(true);
    f.evaluate.mockResolvedValue({ ok: true, value: { available: true } });
    expect(await f.controller.probe(identity.origin)).toMatchObject({ available: true });
  });

  it("rejects very long property names before serialization and omits nonenumerable hooks", () => {
    const getter = vi.fn();
    const value = Object.defineProperty({}, "toJSON", { get: getter });
    expect(boundedWebMcpJson(value, { maxBytes: 100, maxDepth: 2, maxProperties: 2 })).toEqual({});
    expect(getter).not.toHaveBeenCalled();
    expect(() => boundedWebMcpJson({ ["x".repeat(10_000)]: 1 }, { maxBytes: 100, maxDepth: 2, maxProperties: 2 })).toThrow(/key limit/);
  });
});
