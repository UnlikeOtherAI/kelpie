import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createHash } from "node:crypto";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { buildDownloadUrl, downloadModel, parseHuggingFaceUrl } from "../../src/ai/download.js";

function sha256For(input: string): string {
  return createHash("sha256").update(input).digest("hex");
}

describe("Hugging Face download", () => {
  const originalFetch = globalThis.fetch;
  let dir: string;

  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), "kelpie-download-"));
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
    rmSync(dir, { recursive: true, force: true });
  });

  it("builds a download URL from repo and file", () => {
    const url = buildDownloadUrl("bartowski/gemma-4-E2B-it-GGUF", "gemma-4-E2B-it-Q4_K_M.gguf");

    expect(url).toBe("https://huggingface.co/bartowski/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf");
  });

  it("parses a full HF URL into repo and file", () => {
    const result = parseHuggingFaceUrl("https://huggingface.co/TheBloke/some-model-GGUF/resolve/main/model.Q4_K_M.gguf");

    expect(result).toEqual({ repo: "TheBloke/some-model-GGUF", file: "model.Q4_K_M.gguf" });
  });

  it("parses a repo/file shorthand", () => {
    const result = parseHuggingFaceUrl("TheBloke/some-model-GGUF/model.Q4_K_M.gguf");

    expect(result).toEqual({ repo: "TheBloke/some-model-GGUF", file: "model.Q4_K_M.gguf" });
  });

  it("rejects malformed Hugging Face input", () => {
    expect(() => parseHuggingFaceUrl("not-a-valid-model")).toThrow("INVALID_HUGGING_FACE_URL");
  });

  it("downloads a file atomically and verifies checksum", async () => {
    const destPath = join(dir, "model.gguf");
    const content = "hello from kelpie";
    const progress: { downloaded: number; total?: number }[] = [];

    globalThis.fetch = vi.fn(async () =>
      new Response(content, {
        status: 200,
        headers: { "Content-Length": String(content.length) },
      }),
    ) as typeof fetch;

    await downloadModel(
      "https://example.com/model.gguf",
      destPath,
      sha256For(content),
      (downloaded, total) => {
        progress.push({ downloaded, total });
      },
    );

    expect(readFileSync(destPath, "utf8")).toBe(content);
    expect(existsSync(`${destPath}.tmp`)).toBe(false);
    expect(existsSync(join(dir, ".downloading"))).toBe(false);
    expect(progress.at(-1)).toEqual({ downloaded: content.length, total: content.length });
  });

  it("removes the file when checksum verification fails", async () => {
    const destPath = join(dir, "model.gguf");

    globalThis.fetch = vi.fn(async () => new Response("wrong-data", { status: 200 })) as typeof fetch;

    await expect(downloadModel("https://example.com/model.gguf", destPath, sha256For("expected"))).rejects.toThrow(
      "CHECKSUM_MISMATCH",
    );
    expect(existsSync(destPath)).toBe(false);
    expect(existsSync(`${destPath}.tmp`)).toBe(false);
    expect(existsSync(join(dir, ".downloading"))).toBe(false);
  });

  it("refuses to start when another live process holds the download lock", async () => {
    const destPath = join(dir, "model.gguf");
    writeFileSync(
      join(dir, ".downloading"),
      JSON.stringify({ pid: process.pid, startedAt: "2026-04-02T00:00:00.000Z" }),
    );

    globalThis.fetch = vi.fn() as typeof fetch;

    await expect(downloadModel("https://example.com/model.gguf", destPath, "")).rejects.toThrow("DOWNLOAD_IN_PROGRESS");
    expect(globalThis.fetch).not.toHaveBeenCalled();
  });

  it("cleans stale lock and temp files before retrying a crashed download", async () => {
    const destPath = join(dir, "model.gguf");
    const tmpPath = `${destPath}.tmp`;
    const lockPath = join(dir, ".downloading");
    const content = "fresh-data";

    writeFileSync(lockPath, JSON.stringify({ pid: 999999, startedAt: "2026-04-02T00:00:00.000Z" }));
    writeFileSync(tmpPath, "partial");
    globalThis.fetch = vi.fn(async () => new Response(content, { status: 200 })) as typeof fetch;

    await downloadModel("https://example.com/model.gguf", destPath, sha256For(content));

    expect(readFileSync(destPath, "utf8")).toBe(content);
    expect(existsSync(tmpPath)).toBe(false);
    expect(existsSync(lockPath)).toBe(false);
  });
});
