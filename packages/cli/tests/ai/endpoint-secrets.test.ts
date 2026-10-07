import { Readable } from "node:stream";
import { describe, expect, it } from "vitest";
import {
  ApiKeyInputError,
  REDACTED,
  readApiKeyFromEnv,
  readApiKeyFromStream,
  redactSecrets,
} from "../../src/ai/endpoint-secrets.js";

const KEY = "sk-fixture-0123456789abcdef";

describe("readApiKeyFromEnv", () => {
  it("reads and trims the named variable", () => {
    expect(readApiKeyFromEnv("STRATA_KEY", { STRATA_KEY: ` ${KEY}\n` })).toBe(KEY);
  });

  it("fails on a missing, empty or invalid variable without echoing values", () => {
    expect(() => readApiKeyFromEnv("NOPE", {})).toThrow(ApiKeyInputError);
    expect(() => readApiKeyFromEnv("EMPTY", { EMPTY: "  " })).toThrow(/not set or is empty/);
    expect(() => readApiKeyFromEnv("1BAD", { "1BAD": KEY })).toThrow(/not a valid environment variable name/);
  });
});

describe("readApiKeyFromStream", () => {
  it("reads a piped key and drops the trailing newline", async () => {
    await expect(readApiKeyFromStream(Readable.from([Buffer.from(KEY.slice(0, 5)), Buffer.from(`${KEY.slice(5)}\n`)]))).resolves.toBe(KEY);
  });

  it("rejects empty and multi-line input", async () => {
    await expect(readApiKeyFromStream(Readable.from([""]))).rejects.toThrow(/No API key/);
    await expect(readApiKeyFromStream(Readable.from(["a-key\nanother\n"]))).rejects.toThrow(/several lines/);
  });
});

describe("redactSecrets", () => {
  it("masks secret-named fields, known secret substrings and Bearer tokens", () => {
    const input = {
      success: false,
      apiKey: KEY,
      endpoint: { hasApiKey: true, headers: { Authorization: `Bearer ${KEY}` } },
      error: { code: "ENDPOINT_AUTH_FAILED", message: `upstream said: key ${KEY} rejected; Bearer abc.def` },
      list: [KEY, 3, null],
    };
    const output = redactSecrets(input, [KEY]);
    const text = JSON.stringify(output);
    expect(text).not.toContain(KEY);
    expect(text).not.toContain("abc.def");
    expect(output.apiKey).toBe(REDACTED);
    expect(output.endpoint.hasApiKey).toBe(true);
    expect(output.endpoint.headers.Authorization).toBe(REDACTED);
    expect(output.list).toEqual([REDACTED, 3, null]);
    expect(output.error.code).toBe("ENDPOINT_AUTH_FAILED");
  });

  it("leaves unrelated data untouched and does not mutate its input", () => {
    const input = { success: true, endpoints: [{ id: "e1", name: "Strata", hasApiKey: false, apiKey: "" }] };
    const output = redactSecrets(input, ["ab"]);
    expect(output).toEqual(input);
    expect(output).not.toBe(input);
  });
});
