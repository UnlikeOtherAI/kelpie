import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Readable } from "node:stream";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { addDevice, clearDevices } from "../../src/discovery/registry.js";
import { createProgram } from "../../src/program.js";
import { cookieBatches, readCookieInput } from "../../src/commands/cookie-options.js";
import type { DiscoveredDevice } from "../../src/types.js";

const device: DiscoveredDevice = {
  id: "test-device",
  name: "Test Device",
  ip: "192.168.1.42",
  port: 8420,
  platform: "macos",
  model: "Mac",
  width: 1440,
  height: 900,
  version: "1.0.0",
  lastSeen: Date.now(),
};

const cookie = (index: number) => ({
  name: `c${String(index)}`,
  value: "v",
  domain: ".example.com",
  path: "/",
  expires: null,
  httpOnly: true,
  secure: true,
  sameSite: "Lax",
});

let dir: string;
let printed: string[];

function writeJson(name: string, value: unknown): string {
  const path = join(dir, name);
  writeFileSync(path, typeof value === "string" ? value : JSON.stringify(value));
  return path;
}

function mockFetch(reply: (body: Record<string, unknown> | undefined) => unknown): void {
  globalThis.fetch = vi.fn(async (_url: string, init?: RequestInit) => {
    const body = init?.body ? JSON.parse(init.body as string) as Record<string, unknown> : undefined;
    return new Response(JSON.stringify(reply(body)), { status: 200, headers: { "Content-Type": "application/json" } });
  }) as unknown as typeof fetch;
}

const calls = () => (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls;
const url = (index = 0) => calls()[index]?.[0] as string;
const body = (index = 0) => {
  const init = calls()[index]?.[1] as RequestInit | undefined;
  return init?.body ? JSON.parse(init.body as string) : undefined;
};
const lastPrinted = () => JSON.parse(printed.at(-1) ?? "null");

async function run(...args: string[]): Promise<void> {
  const program = createProgram("0.0.0-test");
  program.exitOverride();
  program.configureOutput({ writeOut: () => undefined, writeErr: () => undefined });
  await program.parseAsync(["node", "kelpie", ...args, "--device", "test-device"]);
}

describe("cookie commands over the wire", () => {
  const originalFetch = globalThis.fetch;

  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), "kelpie-cookies-"));
    printed = [];
    vi.spyOn(console, "log").mockImplementation((line: string) => { printed.push(line); });
    clearDevices();
    addDevice(device);
    process.exitCode = undefined;
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
    rmSync(dir, { recursive: true, force: true });
    clearDevices();
    process.exitCode = undefined;
    vi.restoreAllMocks();
  });

  it("cookies list keeps today's empty body", async () => {
    mockFetch(() => ({ success: true, cookies: [], count: 0 }));
    await run("cookies", "list");
    expect(url()).toBe("http://192.168.1.42:8420/v1/get-cookies");
    expect(body()).toEqual({});
  });

  it("cookies list --all --domain --partition reads a whole partition store", async () => {
    mockFetch(() => ({ success: true, cookies: [], count: 0, complete: true }));
    await run("cookies", "list", "--all", "--domain", "example.com", "--partition", "work");
    expect(body()).toEqual({ partition: "work", all: true, domain: "example.com" });
  });

  it("cookies list --all targets a tab through the global --tab-id lease", async () => {
    mockFetch(() => ({ success: true, cookies: [], count: 0 }));
    await run("--tab-id", "t1", "--tab-generation", "3", "cookies", "list", "--all");
    expect(body()).toEqual({ all: true, tabId: "t1", generation: 3 });
  });

  it("cookies list refuses an invalid partition and a tab with a partition", async () => {
    mockFetch(() => ({ success: true }));
    await run("cookies", "list", "--all", "--partition", "default");
    expect(lastPrinted().error.code).toBe("INVALID_PARTITION");
    await run("--tab-id", "t1", "cookies", "list", "--partition", "work");
    expect(lastPrinted().error.code).toBe("INVALID_PARAMS");
    expect(calls()).toHaveLength(0);
    expect(process.exitCode).toBe(1);
  });

  it("cookies import sends a saved listing to set-cookies unchanged", async () => {
    mockFetch(() => ({ success: true, set: 2, failed: [] }));
    const file = writeJson("cookies.json", { success: true, cookies: [cookie(0), { ...cookie(1), extra: 1 }], count: 2 });
    await run("cookies", "import", file, "--partition", "work");
    expect(url()).toBe("http://192.168.1.42:8420/v1/set-cookies");
    expect(body()).toEqual({ partition: "work", cookies: [cookie(0), cookie(1)] });
    expect(lastPrinted()).toEqual({ success: true, set: 2, failed: [] });
  });

  it("cookies import --tab writes into that tab's store", async () => {
    mockFetch(() => ({ success: true, set: 1, failed: [] }));
    await run("cookies", "import", writeJson("one.json", [cookie(0)]), "--tab", "t9");
    expect(body()).toEqual({ tabId: "t9", cookies: [cookie(0)] });
  });

  it("cookies import splits large files into 500-cookie batches and reports file positions", async () => {
    mockFetch((sent) => {
      const batch = sent?.cookies as unknown[];
      return { success: true, set: batch.length - 1, failed: [{ index: 0, name: "x", domain: ".example.com", error: "refused" }] };
    });
    await run("cookies", "import", writeJson("many.json", Array.from({ length: 501 }, (_, index) => cookie(index))));
    expect(calls()).toHaveLength(2);
    expect((body(0).cookies as unknown[]).length).toBe(500);
    expect((body(1).cookies as unknown[]).length).toBe(1);
    expect(body(1)).not.toHaveProperty("tabId");
    expect(lastPrinted()).toEqual({
      success: true,
      set: 499,
      failed: [
        { index: 0, name: "x", domain: ".example.com", error: "refused" },
        { index: 500, name: "x", domain: ".example.com", error: "refused" },
      ],
    });
  });

  it("cookies import stops at a failed batch and says how far it got", async () => {
    let call = 0;
    mockFetch(() => (call++ === 0
      ? { success: true, set: 500, failed: [] }
      : { success: false, error: { code: "WEBVIEW_ERROR", message: "engine gone" } }));
    await run("cookies", "import", writeJson("many.json", Array.from({ length: 600 }, (_, index) => cookie(index))));
    expect(lastPrinted()).toEqual({ success: false, error: { code: "WEBVIEW_ERROR", message: "engine gone" }, set: 500, failed: [] });
    expect(process.exitCode).toBe(1);
  });

  it("cookies import refuses bad input before contacting the device", async () => {
    mockFetch(() => ({ success: true }));
    await run("cookies", "import", writeJson("bad.json", "{not json"));
    expect(lastPrinted().error.message).toContain("is not valid JSON");
    await run("cookies", "import", writeJson("lower.json", [{ ...cookie(0), sameSite: "lax" }]));
    expect(lastPrinted().error.message).toContain("cookie 0 field sameSite");
    await run("cookies", "import", join(dir, "missing.json"));
    expect(lastPrinted().error.message).toContain("Cannot read");
    await run("cookies", "import", writeJson("one.json", [cookie(0)]), "--tab", "t1", "--partition", "work");
    expect(lastPrinted().error.code).toBe("INVALID_PARAMS");
    expect(calls()).toHaveLength(0);
  });

  it("cookies copy sends both stores and the domain; {} is the default store", async () => {
    mockFetch(() => ({ success: true, copied: 3, failed: [] }));
    await run("cookies", "copy", "--to-tab", "t2", "--domain", "example.com");
    expect(url()).toBe("http://192.168.1.42:8420/v1/copy-cookies");
    expect(body()).toEqual({ from: {}, to: { tabId: "t2" }, domain: "example.com" });
  });

  it("cookies copy from a partition back into the default store", async () => {
    mockFetch(() => ({ success: true, copied: 1, failed: [] }));
    await run("cookies", "copy", "--from-partition", "work");
    expect(body()).toEqual({ from: { partition: "work" }, to: {} });
  });

  it("cookies copy refuses the same store, conflicting flags and the global tab lease", async () => {
    mockFetch(() => ({ success: true }));
    await run("cookies", "copy");
    expect(lastPrinted().error.code).toBe("INVALID_PARAMS");
    await run("cookies", "copy", "--from-partition", "work", "--to-partition", "work");
    expect(lastPrinted().error.code).toBe("INVALID_PARAMS");
    await run("cookies", "copy", "--from-tab", "a", "--from-partition", "work");
    expect(lastPrinted().error.message).toContain("--from-tab or --from-partition");
    await run("--tab-id", "t1", "cookies", "copy", "--to-tab", "t2");
    expect(lastPrinted().error.message).toContain("not --tab-id");
    expect(calls()).toHaveLength(0);
  });

  it("cookies sync-status maps to POST /v1/get-cookie-sync-status with no body", async () => {
    mockFetch(() => ({ success: true, supported: false, reason: "signed-out", signedIn: false, listening: false, peers: [], store: {} }));
    await run("cookies", "sync-status");
    expect(url()).toBe("http://192.168.1.42:8420/v1/get-cookie-sync-status");
    expect(body()).toBeUndefined();
  });
});

describe("cookie input", () => {
  it("reads a JSON array from stdin", async () => {
    const cookies = await readCookieInput("-", Readable.from([JSON.stringify([cookie(0)])]));
    expect(cookies).toEqual([cookie(0)]);
  });

  it("refuses JSON that holds no cookie list", async () => {
    await expect(readCookieInput("-", Readable.from(['{"count":1}']))).rejects.toThrow("JSON array of cookies");
  });

  it("always yields at least one batch so an empty file still reaches the device", () => {
    expect(cookieBatches([])).toEqual([[]]);
  });
});
