import { afterEach, describe, expect, it, vi } from "vitest";
import { addDevice, clearDevices } from "../../src/discovery/registry.js";
import { createProgram } from "../../src/program.js";
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

function mockFetch(response: unknown, status = 200): void {
  globalThis.fetch = vi.fn(async () =>
    new Response(JSON.stringify(response), {
      status,
      headers: { "Content-Type": "application/json" },
    }),
  ) as typeof fetch;
}

function capturedUrl(): string {
  return (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0]?.[0] as string;
}

function capturedBody(): Record<string, unknown> | undefined {
  const init = (globalThis.fetch as ReturnType<typeof vi.fn>).mock.calls[0]?.[1] as RequestInit | undefined;
  return init?.body ? JSON.parse(init.body as string) : undefined;
}

function makeProgram() {
  const program = createProgram("0.0.0-test");
  program.exitOverride();
  program.configureOutput({ writeOut: () => undefined, writeErr: () => undefined });
  return program;
}

describe("CLI program compatibility", () => {
  const originalFetch = globalThis.fetch;

  afterEach(() => {
    globalThis.fetch = originalFetch;
    vi.restoreAllMocks();
    clearDevices();
    process.exitCode = undefined;
  });

  it("treats a bare URL argument as navigate shorthand", async () => {
    mockFetch({ success: true, url: "https://example.com/app", title: "Example", loadTime: 10 });
    addDevice(device);
    vi.spyOn(console, "log").mockImplementation(() => undefined);

    await makeProgram().parseAsync([
      "node",
      "kelpie",
      "https://example.com/app",
      "--device",
      "test-device",
    ]);

    expect(capturedUrl()).toBe("http://192.168.1.42:8420/v1/navigate");
    expect(capturedBody()).toEqual({ url: "https://example.com/app" });
  });

  it("keeps unknown non-URL arguments as command errors", async () => {
    const parse = makeProgram().parseAsync(["node", "kelpie", "not-a-command"]);

    await expect(parse).rejects.toMatchObject({
      code: "commander.error",
      message: "unknown command 'not-a-command'",
    });
  });

  it.each(["--tabId", "--tab-id"])("accepts %s after a subcommand", async (flag) => {
    mockFetch({ success: true, text: "hello" });
    addDevice(device);
    vi.spyOn(console, "log").mockImplementation(() => undefined);

    await makeProgram().parseAsync([
      "node",
      "kelpie",
      "--device",
      "test-device",
      "page-text",
      flag,
      "tab-123",
    ]);

    expect(capturedBody()).toEqual({ mode: "readable", tabId: "tab-123" });
  });
});
