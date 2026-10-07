import { describe, expect, it } from "vitest";
import { isLoopbackHost, normalizeEndpointUrl } from "../../src/ai/endpoint-url.js";

function ok(input: string): string {
  const result = normalizeEndpointUrl(input);
  if (!result.ok) throw new Error(`expected ${input} to normalise, got ${result.message}`);
  return result.baseURL;
}

function rejected(input: string): string {
  const result = normalizeEndpointUrl(input);
  if (result.ok) throw new Error(`expected ${input} to be rejected, got ${result.baseURL}`);
  expect(result.code).toBe("INVALID_ENDPOINT_URL");
  return result.message;
}

describe("normalizeEndpointUrl — contract examples", () => {
  it.each([
    ["http://127.0.0.1:18880/v1/", "http://127.0.0.1:18880/v1"],
    ["http://studio.local:1234", "http://studio.local:1234/v1"],
    ["https://host/openai/v1/chat/completions", "https://host/openai/v1"],
    ["http://[::1]:8080/v1", "http://[::1]:8080/v1"],
  ])("%s → %s", (input, expected) => {
    expect(ok(input)).toBe(expected);
  });
});

describe("normalizeEndpointUrl — normalisation", () => {
  it.each([
    ["  http://10.0.0.5:8000/v1  ", "http://10.0.0.5:8000/v1"],
    ["HTTP://Studio.LOCAL:1234/V1", "http://studio.local:1234/V1"],
    ["http://host//openai///v1//", "http://host/openai/v1"],
    ["http://host:1234/v1/models", "http://host:1234/v1"],
    ["http://host:1234/v1/completions", "http://host:1234/v1"],
    ["http://host:1234/v1/embeddings/", "http://host:1234/v1"],
    ["http://host:1234/chat/completions", "http://host:1234/v1"],
    ["http://host:1234/", "http://host:1234/v1"],
    ["https://api.example.com", "https://api.example.com/v1"],
    ["http://[FE80::1]:9000/api", "http://[fe80::1]:9000/api"],
    ["http://host:00080/v1", "http://host:80/v1"],
    ["http://host:65535", "http://host:65535/v1"],
    ["http://host:1/x/v1/chat/completions/", "http://host:1/x/v1"],
  ])("%s → %s", (input, expected) => {
    expect(ok(input)).toBe(expected);
  });

  it("never yields a duplicate /v1 or a double slash", () => {
    for (const input of ["http://h/v1/v1/models", "http://h//v1//chat//completions"]) {
      const base = ok(input);
      expect(base).not.toMatch(/[^:]\/\//);
    }
    expect(ok("http://h//v1//chat//completions")).toBe("http://h/v1");
  });
});

describe("normalizeEndpointUrl — rejections", () => {
  it.each([
    [""],
    ["   "],
    ["ftp://host/v1"],
    ["ws://host:1234/v1"],
    ["host:1234/v1"],
    ["http://"],
    ["http:///v1"],
    ["http://user:pass@host:1234/v1"],
    ["http://token@host/v1"],
    ["http://host:1234/v1?key=abc"],
    ["http://host:1234/v1#frag"],
    ["http://host:0/v1"],
    ["http://host:65536/v1"],
    ["http://host:99999/v1"],
    ["http://host:-1/v1"],
    ["http://host:abc/v1"],
    ["http://ho st/v1"],
    ["http://[zz::1]/v1"],
  ])("rejects %j", (input) => {
    expect(rejected(input).length).toBeGreaterThan(0);
  });

  it("does not echo user info back in the message", () => {
    expect(rejected("http://alice:s3cret@host/v1")).not.toContain("s3cret");
  });
});

describe("loopback detection", () => {
  it.each([
    ["http://localhost:1234", true],
    ["http://127.0.0.1:18880/v1", true],
    ["http://127.4.5.6/v1", true],
    ["http://[::1]:8080/v1", true],
    ["http://192.168.1.20:1234/v1", false],
    ["http://studio.local:1234", false],
  ])("%s loopback=%s", (input, expected) => {
    const result = normalizeEndpointUrl(input);
    expect(result.ok && result.loopback).toBe(expected);
  });

  it("matches bare and bracketed hosts", () => {
    expect(isLoopbackHost("LOCALHOST")).toBe(true);
    expect(isLoopbackHost("[::1]")).toBe(true);
    expect(isLoopbackHost("128.0.0.1")).toBe(false);
  });
});
