import { afterEach, describe, expect, it, vi } from "vitest";
import {
  buildOllamaGenerateRequest,
  DEFAULT_OLLAMA_ENDPOINT,
  detectOllama,
  isOllamaModelId,
  listOllamaModels,
  ollamaGenerate,
  OLLAMA_PREFIX,
  parseOllamaModelId,
} from "../../src/ai/ollama.js";

describe("Ollama integration", () => {
  const originalFetch = globalThis.fetch;

  afterEach(() => {
    globalThis.fetch = originalFetch;
  });

  it("exports the Ollama model prefix and default endpoint", () => {
    expect(OLLAMA_PREFIX).toBe("ollama:");
    expect(DEFAULT_OLLAMA_ENDPOINT).toBe("http://localhost:11434");
  });

  it("detects Ollama model IDs by prefix", () => {
    expect(isOllamaModelId("ollama:llama3.2:3b")).toBe(true);
    expect(isOllamaModelId("gemma-4-e2b-q4")).toBe(false);
  });

  it("extracts the model name from a prefixed ID", () => {
    expect(parseOllamaModelId("ollama:llava:7b")).toBe("llava:7b");
    expect(parseOllamaModelId("ollama:llama3.2:3b")).toBe("llama3.2:3b");
  });

  it("rejects invalid Ollama model IDs", () => {
    expect(() => parseOllamaModelId("gemma-4-e2b-q4")).toThrow("INVALID_OLLAMA_MODEL_ID");
  });

  it("detects a reachable Ollama endpoint", async () => {
    globalThis.fetch = vi.fn(async () => new Response(JSON.stringify({ models: [] }), { status: 200 })) as typeof fetch;

    await expect(detectOllama()).resolves.toBe(true);
    expect(globalThis.fetch).toHaveBeenCalledWith(`${DEFAULT_OLLAMA_ENDPOINT}/api/tags`, expect.any(Object));
  });

  it("lists available Ollama models", async () => {
    globalThis.fetch = vi.fn(async () =>
      new Response(
        JSON.stringify({
          models: [
            {
              name: "llava:7b",
              size: 4_700_000_000,
              digest: "abc123",
              modified_at: "2026-04-02T00:00:00Z",
            },
          ],
        }),
        {
          status: 200,
          headers: { "Content-Type": "application/json" },
        },
      ),
    ) as typeof fetch;

    await expect(listOllamaModels()).resolves.toEqual([
      {
        name: "llava:7b",
        size: 4_700_000_000,
        digest: "abc123",
        modifiedAt: "2026-04-02T00:00:00Z",
      },
    ]);
  });

  it("builds a generate request for text and images", () => {
    const req = buildOllamaGenerateRequest("llava:7b", "describe this", {
      maxTokens: 256,
      temperature: 0.2,
      image: "base64data",
    });

    expect(req).toEqual({
      model: "llava:7b",
      prompt: "describe this",
      stream: false,
      images: ["base64data"],
      options: {
        num_predict: 256,
        temperature: 0.2,
      },
    });
  });

  it("posts a generate request and normalizes the response shape", async () => {
    globalThis.fetch = vi.fn(async (_url: string | URL | Request, init?: RequestInit) => {
      expect(_url).toBe(`${DEFAULT_OLLAMA_ENDPOINT}/api/generate`);
      expect(init?.method).toBe("POST");
      expect(init?.headers).toEqual({ "Content-Type": "application/json" });
      expect(JSON.parse(String(init?.body))).toEqual({
        model: "llava:7b",
        prompt: "describe this",
        stream: false,
        options: {
          num_predict: 32,
        },
      });

      return new Response(
        JSON.stringify({
          response: "It is a pricing page.",
          total_duration: 1234,
          eval_count: 50,
        }),
        {
          status: 200,
          headers: { "Content-Type": "application/json" },
        },
      );
    }) as typeof fetch;

    await expect(
      ollamaGenerate(
        DEFAULT_OLLAMA_ENDPOINT,
        buildOllamaGenerateRequest("llava:7b", "describe this", { maxTokens: 32 }),
      ),
    ).resolves.toEqual({
      response: "It is a pricing page.",
      totalDuration: 1234,
      evalCount: 50,
    });
  });
});
