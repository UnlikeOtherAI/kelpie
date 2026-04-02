import { describe, it, expect } from "vitest";
import { getApprovedModels, findModel } from "../../src/ai/models.js";
import { buildDownloadUrl } from "../../src/ai/download.js";
import { browserTools, cliTools } from "../../src/mcp/tools.js";
import {
  BrowserMcpTools,
  CliMcpTools,
  httpToMcp,
  BrowserToolUnsupportedPlatforms,
} from "@unlikeotherai/mollotov-shared";

describe("AI integration", () => {
  it("all approved models have valid HuggingFace URLs", () => {
    for (const model of getApprovedModels()) {
      const url = buildDownloadUrl(model.huggingFaceRepo, model.huggingFaceFile);
      expect(url).toMatch(/^https:\/\/huggingface\.co\//);
      expect(url).toMatch(/\.gguf$/);
    }
  });

  it("all approved models have required fields", () => {
    for (const model of getApprovedModels()) {
      expect(model.id).toBeTruthy();
      expect(model.capabilities.length).toBeGreaterThan(0);
      expect(model.platforms.length).toBeGreaterThan(0);
      expect(model.minRamGB).toBeGreaterThan(0);
      expect(model.huggingFaceRepo).toBeTruthy();
      expect(model.huggingFaceFile).toBeTruthy();
      expect(model.sizeBytes).toBeGreaterThan(0);
    }
  });

  it("findModel returns undefined for unknown ID", () => {
    expect(findModel("nonexistent-model")).toBeUndefined();
  });

  it("findModel returns matching model for known ID", () => {
    const models = getApprovedModels();
    for (const model of models) {
      const found = findModel(model.id);
      expect(found).toBeDefined();
      expect(found!.id).toBe(model.id);
    }
  });

  it("AI browser tools are registered in shared BrowserMcpTools", () => {
    const aiToolNames = browserTools
      .filter((t) => t.name.startsWith("mollotov_ai_"))
      .map((t) => t.name);

    expect(aiToolNames.length).toBe(5);
    for (const name of aiToolNames) {
      expect(BrowserMcpTools).toContain(name);
    }
  });

  it("AI CLI tools are registered in shared CliMcpTools", () => {
    const aiToolNames = cliTools
      .filter((t) => t.name.startsWith("mollotov_ai_"))
      .map((t) => t.name);

    expect(aiToolNames.length).toBe(3);
    for (const name of aiToolNames) {
      expect(CliMcpTools).toContain(name);
    }
  });

  it("AI HTTP endpoints are mapped in httpToMcp", () => {
    const aiMappings = ["ai-status", "ai-load", "ai-unload", "ai-infer", "ai-record"];
    for (const endpoint of aiMappings) {
      expect(httpToMcp).toHaveProperty(endpoint);
    }
  });

  it("AI browser tools have linux/windows unsupported platform gates", () => {
    const aiToolNames = browserTools
      .filter((t) => t.name.startsWith("mollotov_ai_"))
      .map((t) => t.name);

    for (const name of aiToolNames) {
      const unsupported = BrowserToolUnsupportedPlatforms[name as keyof typeof BrowserToolUnsupportedPlatforms];
      expect(unsupported).toBeDefined();
      expect(unsupported).toContain("linux");
      expect(unsupported).toContain("windows");
    }
  });
});
