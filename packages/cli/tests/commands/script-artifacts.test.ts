import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve, sep } from "node:path";
import { downloadScriptArtifact } from "../../src/commands/script-artifacts.js";
import { scriptHostBody, redactScriptResult } from "../../src/mcp/script-tools.js";
import type { DiscoveredDevice } from "../../src/types.js";
const send = vi.hoisted(() => vi.fn());
const closeFault = vi.hoisted(() => ({ active: false }));
vi.mock("node:fs/promises", async importOriginal => {
  const actual = await importOriginal<typeof import("node:fs/promises")>();
  return { ...actual, open: async (...args: Parameters<typeof actual.open>) => {
    const handle = await actual.open(...args);
    if (closeFault.active) {
      const close = handle.close.bind(handle);
      handle.close = async () => { await close(); throw new Error("Injected close failure"); };
    }
    return handle;
  } };
});
vi.mock("../../src/client/http-client.js", () => ({ sendCommand: send, createPinnedCommandTransport: (device: DiscoveredDevice) => (method: string, body: unknown, timeout: number) => send(device, method, body, timeout) }));
let directory: string;
beforeEach(async () => { directory = await mkdtemp(join(tmpdir(), "kelpie-artifact-")); send.mockReset(); });
afterEach(async () => {
  closeFault.active = false;
  if (!resolve(directory).startsWith(resolve(tmpdir()) + sep)) throw new Error("Unsafe test cleanup");
  await rm(directory, { recursive: true, force: true });
  vi.unstubAllEnvs();
});
const device = { id: "one", ip: "127.0.0.1", port: 8420, localControlToken: "grant" } as DiscoveredDevice;
describe("authenticated artifact download", () => {
  it("pins the socket, writes verified bytes and refuses overwrite", async () => {
    const bytes = Buffer.from("GIF89a-fixture");
    const sha256 = createHash("sha256").update(bytes).digest("hex");
    const manifest = { id: "id-without-path", mimeType: "image/gif", byteLength: bytes.length, sha256, partial: true, width: 10, height: 10 };
    send.mockResolvedValue({ ok: true, data: { runId: "run", artifactId: "id-without-path", data: bytes.toString("base64"), offset: 0, nextOffset: bytes.length, eof: true, mimeType: "image/gif", byteLength: bytes.length, sha256 } });
    const path = join(directory, "capture.gif");
    await downloadScriptArtifact(device, "run", manifest, path, 5000);
    expect(await readFile(path)).toEqual(bytes);
    expect(send).toHaveBeenCalledWith(device, "getScriptArtifact", { runId: "run", artifactId: manifest.id, offset: 0, length: 262144 }, 5000);
    await expect(downloadScriptArtifact(device, "run", manifest, path, 5000)).rejects.toThrow();
    expect(await readFile(path)).toEqual(bytes);
  });
  it("keeps partial bytes unpromoted when integrity or offsets fail", async () => {
    const manifest = { id: "video", mimeType: "video/mp4", byteLength: 3, sha256: "0".repeat(64), partial: false, width: 10, height: 10 };
    send.mockResolvedValue({ ok: true, data: { runId: "run", artifactId: "video", data: Buffer.from("bad").toString("base64"), offset: 0, nextOffset: 3, eof: true, mimeType: "video/mp4", byteLength: 3, sha256: manifest.sha256 } });
    const path = join(directory, "capture.mp4");
    await expect(downloadScriptArtifact(device, "run", manifest, path, 5000)).rejects.toThrow("integrity");
    await expect(readFile(path)).rejects.toThrow();
    expect(await readdir(directory)).toEqual([]);
  });
});
describe("host workflow bindings", () => {
  it("strips environment mappings and redacts echoed short secrets", () => {
    vi.stubEnv("WORKFLOW_TEST_SECRET", "xy");
    const body = scriptHostBody({ device: "one", version: 1, tabId: "tab", secretEnv: { password: "WORKFLOW_TEST_SECRET" }, actions: [{ action: "fill", target: { label: "Password" }, text: { secret: "password" } }] });
    expect(body).not.toHaveProperty("secretEnv");
    expect(redactScriptResult({ error: "echo xy", nested: ["xy"] }, body)).toEqual({ error: "echo [REDACTED]", nested: ["[REDACTED]"] });
  });
  it("refuses secret capture and invalid strict actions without disclosing values", () => {
    vi.stubEnv("WORKFLOW_TEST_SECRET", "do-not-print");
    expect(() => scriptHostBody({ version: 1, tabId: "tab", capture: { formats: ["gif"] }, secretEnv: { password: "WORKFLOW_TEST_SECRET" }, actions: [{ action: "fill", target: { label: "Password" }, text: { secret: "password" } }] })).toThrow("Invalid workflow or unavailable input/secret");
    expect(() => scriptHostBody({ version: 1, tabId: "tab", actions: [{ action: "evaluate", expression: "alert(1)" }] })).toThrow("Invalid workflow");
  });
});

describe("hostile and interrupted artifact transfers", () => {
  const bytes = Buffer.from("PNG-fixture");
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  const manifest = { id: "../../opaque-not-a-path", mimeType: "image/png", byteLength: bytes.length, sha256, partial: false, width: 10, height: 10 };
  const valid = { runId: "run", artifactId: manifest.id, data: bytes.toString("base64"), offset: 0, nextOffset: bytes.length, eof: true, mimeType: "image/png", byteLength: bytes.length, sha256 };
  it.each([
    { artifactId: "different" }, { runId: "other" }, { offset: 1 }, { nextOffset: 999 },
    { eof: false }, { mimeType: "image/gif" }, { byteLength: 999 }, { sha256: "1".repeat(64) },
  ])("rejects chunk metadata changes and removes only its own temporary file", async changes => {
    await writeFile(join(directory, "keep.txt"), "user-owned");
    send.mockResolvedValue({ ok: true, data: { ...valid, ...changes } });
    await expect(downloadScriptArtifact(device, "run", manifest, join(directory, "capture.png"), 5000)).rejects.toThrow();
    expect(await readdir(directory)).toEqual(["keep.txt"]);
    expect(await readFile(join(directory, "keep.txt"), "utf8")).toBe("user-owned");
  });
  it("removes only its own temporary file when close fails after integrity verification", async () => {
    closeFault.active = true;
    send.mockResolvedValue({ ok: true, data: valid });
    await expect(downloadScriptArtifact(device, "run", manifest, join(directory, "capture.png"), 5000)).rejects.toThrow("Injected close failure");
    expect(await readdir(directory)).toEqual([]);
  });
  it("keeps remote identifiers out of local paths and preserves unrelated partial files", async () => {
    await writeFile(join(directory, "capture.png.partial"), "user-owned");
    send.mockResolvedValue({ ok: true, data: valid });
    await downloadScriptArtifact(device, "run", manifest, join(directory, "capture.png"), 5000);
    expect(await readFile(join(directory, "capture.png"))).toEqual(bytes);
    expect(await readFile(join(directory, "capture.png.partial"), "utf8")).toBe("user-owned");
  });
  it("recovers from a failed later chunk without leaving a blocking partial file", async () => {
    const all = Buffer.alloc(262145, 65);
    const largeHash = createHash("sha256").update(all).digest("hex");
    const large = { ...manifest, byteLength: all.length, sha256: largeHash };
    send.mockResolvedValueOnce({ ok: true, data: { ...valid, byteLength: all.length, sha256: largeHash, data: all.subarray(0, 262144).toString("base64"), nextOffset: 262144, eof: false } });
    send.mockResolvedValueOnce({ ok: false, status: 408, data: {} });
    const destination = join(directory, "capture.png");
    await expect(downloadScriptArtifact(device, "run", large, destination, 5000)).rejects.toThrow("Artifact request failed");
    expect(await readdir(directory)).toEqual([]);
    send.mockResolvedValue({ ok: true, data: valid });
    await downloadScriptArtifact(device, "run", manifest, destination, 5000);
    expect(await readFile(destination)).toEqual(bytes);
  });
});
