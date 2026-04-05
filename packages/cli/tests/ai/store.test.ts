import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { ModelStore } from "../../src/ai/store.js";

describe("ModelStore", () => {
  let dir: string;
  let store: ModelStore;

  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), "kelpie-models-"));
    store = new ModelStore(dir);
  });

  afterEach(() => {
    rmSync(dir, { recursive: true, force: true });
  });

  it("lists no models initially", () => {
    expect(store.listDownloaded()).toEqual([]);
  });

  it("reports model not downloaded", () => {
    expect(store.isDownloaded("gemma-4-e2b-q4")).toBe(false);
    expect(store.getModelPath("gemma-4-e2b-q4")).toBeUndefined();
  });

  it("registers a model, writes metadata, and exposes paths", () => {
    store.register("gemma-4-e2b-q4", {
      name: "Gemma 4 E2B Q4",
      capabilities: ["text", "vision", "audio"],
    });

    const modelDir = store.getModelDir("gemma-4-e2b-q4");
    const metadataPath = join(modelDir, "metadata.json");
    const registryPath = join(dir, "registry.json");

    expect(store.isDownloaded("gemma-4-e2b-q4")).toBe(true);
    expect(store.getModelPath("gemma-4-e2b-q4")).toBe(join(modelDir, "model.gguf"));
    expect(store.listDownloaded()).toEqual([
      {
        id: "gemma-4-e2b-q4",
        dir: modelDir,
        path: join(modelDir, "model.gguf"),
        meta: {
          name: "Gemma 4 E2B Q4",
          capabilities: ["text", "vision", "audio"],
        },
      },
    ]);
    expect(JSON.parse(readFileSync(metadataPath, "utf8"))).toEqual({
      name: "Gemma 4 E2B Q4",
      capabilities: ["text", "vision", "audio"],
    });
    expect(JSON.parse(readFileSync(registryPath, "utf8"))).toEqual({
      models: {
        "gemma-4-e2b-q4": {
          name: "Gemma 4 E2B Q4",
          capabilities: ["text", "vision", "audio"],
        },
      },
    });
  });

  it("removes a model from disk and the registry", () => {
    store.register("gemma-4-e2b-q4", { name: "Gemma 4", capabilities: ["text"] });

    const modelDir = store.getModelDir("gemma-4-e2b-q4");
    store.remove("gemma-4-e2b-q4");

    expect(store.isDownloaded("gemma-4-e2b-q4")).toBe(false);
    expect(store.getModelPath("gemma-4-e2b-q4")).toBeUndefined();
    expect(existsSync(modelDir)).toBe(false);
    expect(store.listDownloaded()).toEqual([]);
  });

  it("removes orphaned temp and stale lock files", () => {
    const orphanDir = store.getModelDir("gemma-4-e2b-q4");
    const lockPath = join(orphanDir, ".downloading");
    const tmpPath = join(orphanDir, "model.gguf.tmp");

    writeFileSync(lockPath, JSON.stringify({ pid: 999999, startedAt: "2026-04-02T00:00:00.000Z" }));
    writeFileSync(tmpPath, "partial");

    store.cleanOrphans();

    expect(existsSync(lockPath)).toBe(false);
    expect(existsSync(tmpPath)).toBe(false);
  });
});
