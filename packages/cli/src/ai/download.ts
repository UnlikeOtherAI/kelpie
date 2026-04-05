import { createHash } from "node:crypto";
import { mkdir, open, readFile, rename, rm, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";

const HUGGING_FACE_HOST = "huggingface.co";
const LOCK_FILE = ".downloading";

export interface ParsedHuggingFaceUrl {
  repo: string;
  file: string;
}

export type DownloadProgressCallback = (downloadedBytes: number, totalBytes?: number) => void;

interface DownloadLock {
  pid: number;
  startedAt: string;
}

function isPidAlive(pid: number): boolean {
  if (!Number.isInteger(pid) || pid <= 0) {
    return false;
  }

  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function checksumMatches(actual: string, expected: string): boolean {
  return actual.toLowerCase() === expected.toLowerCase();
}

async function readLock(lockPath: string): Promise<DownloadLock | undefined> {
  try {
    const content = await readFile(lockPath, "utf8");
    return JSON.parse(content) as DownloadLock;
  } catch {
    return undefined;
  }
}

async function cleanupStaleArtifacts(lockPath: string, tmpPath: string): Promise<boolean> {
  const lock = await readLock(lockPath);
  if (lock && isPidAlive(lock.pid)) {
    return false;
  }

  await rm(lockPath, { force: true });
  await rm(tmpPath, { force: true });
  return true;
}

async function acquireDownloadLock(lockPath: string, tmpPath: string): Promise<void> {
  const payload = JSON.stringify({ pid: process.pid, startedAt: new Date().toISOString() });

  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      await writeFile(lockPath, payload, { flag: "wx" });
      return;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (!message.includes("EEXIST")) {
        throw error;
      }

      const cleaned = await cleanupStaleArtifacts(lockPath, tmpPath);
      if (!cleaned) {
        throw new Error("DOWNLOAD_IN_PROGRESS", { cause: error });
      }
    }
  }

  throw new Error("DOWNLOAD_IN_PROGRESS");
}

export function buildDownloadUrl(repo: string, file: string): string {
  return `https://${HUGGING_FACE_HOST}/${repo}/resolve/main/${file}`;
}

export function parseHuggingFaceUrl(input: string): ParsedHuggingFaceUrl {
  if (input.startsWith("https://") || input.startsWith("http://")) {
    const url = new URL(input);
    if (url.hostname !== HUGGING_FACE_HOST) {
      throw new Error("INVALID_HUGGING_FACE_URL");
    }

    const parts = url.pathname.split("/").filter(Boolean);
    const resolveIndex = parts.indexOf("resolve");
    if (parts.length < 4 || resolveIndex !== 2 || parts[3] !== "main") {
      throw new Error("INVALID_HUGGING_FACE_URL");
    }

    const repo = parts.slice(0, 2).join("/");
    const file = parts.slice(4).join("/");
    if (!repo || !file) {
      throw new Error("INVALID_HUGGING_FACE_URL");
    }

    return { repo, file };
  }

  const parts = input.split("/").filter(Boolean);
  if (parts.length < 3) {
    throw new Error("INVALID_HUGGING_FACE_URL");
  }

  return {
    repo: parts.slice(0, 2).join("/"),
    file: parts.slice(2).join("/"),
  };
}

export async function downloadModel(
  url: string,
  destPath: string,
  sha256: string,
  onProgress?: DownloadProgressCallback,
): Promise<void> {
  const modelDir = dirname(destPath);
  const lockPath = join(modelDir, LOCK_FILE);
  const tmpPath = `${destPath}.tmp`;
  let fileHandle: Awaited<ReturnType<typeof open>> | undefined;

  await mkdir(modelDir, { recursive: true });
  await acquireDownloadLock(lockPath, tmpPath);

  try {
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`DOWNLOAD_FAILED: ${String(response.status)} ${response.statusText}`);
    }

    fileHandle = await open(tmpPath, "w");
    const totalHeader = response.headers.get("content-length");
    const totalBytes = totalHeader ? Number.parseInt(totalHeader, 10) : undefined;
    const hash = createHash("sha256");
    let downloadedBytes = 0;

    if (response.body) {
      const reader = response.body.getReader();
      // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
      while (true) {
        const { done, value } = await reader.read();
        if (done) {
          break;
        }

        await fileHandle.write(value);
        hash.update(value);
        downloadedBytes += value.byteLength;
        onProgress?.(downloadedBytes, totalBytes);
      }
    } else {
      const bytes = new Uint8Array(await response.arrayBuffer());
      await fileHandle.write(bytes);
      hash.update(bytes);
      downloadedBytes = bytes.byteLength;
      onProgress?.(downloadedBytes, totalBytes);
    }

    await fileHandle.close();
    fileHandle = undefined;

    if (sha256.trim() && !checksumMatches(hash.digest("hex"), sha256.trim())) {
      throw new Error("CHECKSUM_MISMATCH");
    }

    await rename(tmpPath, destPath);
  } catch (error) {
    if (fileHandle) {
      await fileHandle.close().catch(() => undefined);
    }
    await rm(tmpPath, { force: true });
    throw error;
  } finally {
    await rm(lockPath, { force: true });
  }
}
