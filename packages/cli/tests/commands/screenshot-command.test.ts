import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { mkdtemp, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { addDevice, clearDevices } from "../../src/discovery/registry.js";
import { createProgram } from "../../src/program.js";
import type { DiscoveredDevice } from "../../src/types.js";

const device: DiscoveredDevice = {
  id: "test-device",
  name: "Test Windows",
  ip: "127.0.0.1",
  port: 8420,
  platform: "windows",
  model: "Kelpie windows",
  width: 0,
  height: 0,
  version: "0.1.1",
  lastSeen: Date.now(),
};

function mockFetch(response: unknown): void {
  globalThis.fetch = vi.fn(async () =>
    new Response(JSON.stringify(response), { status: 200, headers: { "Content-Type": "application/json" } }),
  ) as typeof fetch;
}

function capturedBody(): Record<string, unknown> {
  const init = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0]?.[1] as RequestInit;
  return JSON.parse(init.body as string);
}

async function run(...args: string[]): Promise<void> {
  const program = createProgram("0.0.0-test");
  program.exitOverride();
  program.configureOutput({ writeOut: () => undefined, writeErr: () => undefined });
  await program.parseAsync(["node", "kelpie", ...args, "--device", "test-device"]);
}

describe("kelpie screenshot --max-width", () => {
  const originalFetch = globalThis.fetch;
  let outputDir: string;
  let printed: string[];

  beforeEach(async () => {
    addDevice(device);
    outputDir = await mkdtemp(join(tmpdir(), "kelpie-shot-"));
    printed = [];
    vi.spyOn(console, "log").mockImplementation((line: unknown) => { printed.push(String(line)); });
    process.exitCode = undefined;
  });

  afterEach(async () => {
    globalThis.fetch = originalFetch;
    vi.restoreAllMocks();
    clearDevices();
    process.exitCode = undefined;
    await rm(outputDir, { recursive: true, force: true });
  });

  it("sends maxWidth and quality with a JPEG request and saves a conforming image", async () => {
    mockFetch({ success: true, image: Buffer.from("jpeg").toString("base64"), width: 960, height: 479, format: "jpeg" });

    await run("screenshot", "--image-format", "jpeg", "--quality", "60", "--max-width", "960", "--output", `${outputDir}/`);

    expect(capturedBody()).toEqual({ fullPage: false, format: "jpeg", quality: 60, maxWidth: 960 });
    expect(process.exitCode).toBeUndefined();
    expect(await readdir(outputDir)).toHaveLength(1);
  });

  it("refuses to save an image wider than --max-width", async () => {
    mockFetch({ success: true, image: Buffer.from("png").toString("base64"), width: 1918, height: 957, format: "png" });

    await run("screenshot", "--max-width", "960", "--output", `${outputDir}/`);

    expect(process.exitCode).toBe(1);
    expect(await readdir(outputDir)).toHaveLength(0);
    expect(JSON.parse(printed.join("\n")).error).toMatchObject({ code: "SCREENSHOT_OPTION_UNSUPPORTED", option: "maxWidth" });
  });
});
