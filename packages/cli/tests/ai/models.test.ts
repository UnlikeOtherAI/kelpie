import { describe, expect, it } from "vitest";
import { findModel, getApprovedModels } from "../../src/ai/models.js";

describe("approved model registry", () => {
  it("returns the built-in Gemma models with full metadata", () => {
    const models = getApprovedModels();

    expect(models).toHaveLength(2);
    expect(models).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          id: "gemma-4-e2b-q4",
          name: "Gemma 4 E2B Q4",
          huggingFaceRepo: "bartowski/gemma-4-E2B-it-GGUF",
          huggingFaceFile: "gemma-4-E2B-it-Q4_K_M.gguf",
          sha256: "",
          sizeBytes: 2_500_000_000,
          ramWhenLoadedGB: 3.8,
          capabilities: ["text", "vision", "audio"],
          memory: false,
          platforms: ["macos"],
          minRamGB: 8,
          recommendedRamGB: 16,
          quantization: "Q4_K_M",
          contextWindow: 8192,
          description: expect.objectContaining({
            summary: expect.any(String),
            strengths: expect.any(Array),
            limitations: expect.any(Array),
            bestFor: expect.any(String),
            speedRating: "moderate",
          }),
        }),
        expect.objectContaining({
          id: "gemma-4-e2b-q8",
          name: "Gemma 4 E2B Q8",
          huggingFaceRepo: "bartowski/gemma-4-E2B-it-GGUF",
          huggingFaceFile: "gemma-4-E2B-it-Q8_0.gguf",
          sha256: "",
          sizeBytes: 5_000_000_000,
          ramWhenLoadedGB: 8,
          capabilities: ["text", "vision", "audio"],
          memory: false,
          platforms: ["macos"],
          minRamGB: 16,
          recommendedRamGB: 32,
          quantization: "Q8_0",
          contextWindow: 8192,
          description: expect.objectContaining({
            summary: expect.any(String),
            strengths: expect.any(Array),
            limitations: expect.any(Array),
            bestFor: expect.any(String),
            speedRating: "moderate",
          }),
        }),
      ]),
    );
  });

  it("finds a model by id", () => {
    const model = findModel("gemma-4-e2b-q4");

    expect(model).toBeDefined();
    expect(model?.id).toBe("gemma-4-e2b-q4");
  });

  it("returns undefined for unknown model", () => {
    expect(findModel("nonexistent")).toBeUndefined();
  });
});
