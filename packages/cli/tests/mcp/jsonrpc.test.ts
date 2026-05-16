import { describe, it, expect } from "vitest";
import {
  INVALID_REQUEST_CODE,
  validateEnvelope,
  validatePayload,
} from "../../src/mcp/jsonrpc.js";

describe("validateEnvelope", () => {
  it("accepts a well-formed request", () => {
    expect(validateEnvelope({ jsonrpc: "2.0", id: 1, method: "ping" })).toEqual({ ok: true });
  });

  it("accepts a notification (no id)", () => {
    expect(validateEnvelope({ jsonrpc: "2.0", method: "notify" })).toEqual({ ok: true });
  });

  it("accepts a string id", () => {
    expect(validateEnvelope({ jsonrpc: "2.0", id: "abc", method: "ping" })).toEqual({ ok: true });
  });

  it("accepts a null id on a request (allowed by spec)", () => {
    expect(validateEnvelope({ jsonrpc: "2.0", id: null, method: "ping" })).toEqual({ ok: true });
  });

  it("accepts a successful response", () => {
    expect(validateEnvelope({ jsonrpc: "2.0", id: 1, result: { ok: true } })).toEqual({ ok: true });
  });

  it("accepts an error response", () => {
    expect(
      validateEnvelope({ jsonrpc: "2.0", id: 1, error: { code: -32601, message: "Method not found" } }),
    ).toEqual({ ok: true });
  });

  it("accepts params as object or array", () => {
    expect(validateEnvelope({ jsonrpc: "2.0", id: 1, method: "x", params: { a: 1 } })).toEqual({ ok: true });
    expect(validateEnvelope({ jsonrpc: "2.0", id: 2, method: "x", params: [1, 2] })).toEqual({ ok: true });
  });

  it("rejects non-objects", () => {
    for (const v of [null, undefined, 42, "hi", true, [1]]) {
      const r = validateEnvelope(v);
      expect(r.ok).toBe(false);
      if (!r.ok) expect(r.error.code).toBe(INVALID_REQUEST_CODE);
    }
  });

  it("rejects missing or wrong jsonrpc version", () => {
    const r = validateEnvelope({ id: 1, method: "ping" });
    expect(r.ok).toBe(false);
    const r2 = validateEnvelope({ jsonrpc: "1.0", id: 1, method: "ping" });
    expect(r2.ok).toBe(false);
  });

  it("rejects non-string method on requests", () => {
    const r = validateEnvelope({ jsonrpc: "2.0", id: 1, method: 5 });
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.error.code).toBe(INVALID_REQUEST_CODE);
      expect(r.id).toBe(1);
    }
  });

  it("rejects fractional or non-finite id", () => {
    expect(validateEnvelope({ jsonrpc: "2.0", id: 1.5, method: "x" }).ok).toBe(false);
    expect(validateEnvelope({ jsonrpc: "2.0", id: Number.NaN, method: "x" }).ok).toBe(false);
  });

  it("rejects object/array id", () => {
    expect(validateEnvelope({ jsonrpc: "2.0", id: { a: 1 }, method: "x" }).ok).toBe(false);
    expect(validateEnvelope({ jsonrpc: "2.0", id: [1], method: "x" }).ok).toBe(false);
  });

  it("rejects non-structured params", () => {
    expect(validateEnvelope({ jsonrpc: "2.0", id: 1, method: "x", params: "nope" }).ok).toBe(false);
  });

  it("rejects response with both result and error", () => {
    expect(
      validateEnvelope({ jsonrpc: "2.0", id: 1, result: {}, error: { code: 1, message: "x" } }).ok,
    ).toBe(false);
  });

  it("rejects response with neither result nor error", () => {
    expect(validateEnvelope({ jsonrpc: "2.0", id: 1 }).ok).toBe(false);
  });

  it("rejects response missing id", () => {
    expect(validateEnvelope({ jsonrpc: "2.0", result: {} }).ok).toBe(false);
  });

  it("rejects error response with malformed error object", () => {
    expect(validateEnvelope({ jsonrpc: "2.0", id: 1, error: { message: "x" } }).ok).toBe(false);
    expect(validateEnvelope({ jsonrpc: "2.0", id: 1, error: { code: "x", message: "x" } }).ok).toBe(false);
    expect(validateEnvelope({ jsonrpc: "2.0", id: 1, error: "nope" }).ok).toBe(false);
  });
});

describe("validatePayload", () => {
  it("accepts a batch of valid envelopes", () => {
    expect(
      validatePayload([
        { jsonrpc: "2.0", id: 1, method: "a" },
        { jsonrpc: "2.0", method: "b" },
      ]),
    ).toEqual({ ok: true });
  });

  it("rejects empty batch", () => {
    const r = validatePayload([]);
    expect(r.ok).toBe(false);
  });

  it("rejects batch with one malformed entry", () => {
    const r = validatePayload([
      { jsonrpc: "2.0", id: 1, method: "a" },
      { jsonrpc: "1.0", id: 2, method: "b" },
    ]);
    expect(r.ok).toBe(false);
  });
});
