import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { Command } from "commander";
import { addDevice, clearDevices } from "../../src/discovery/registry.js";
import { registerGroup } from "../../src/commands/group.js";
import type { DiscoveredDevice } from "../../src/types.js";

function makeDevice(overrides: Partial<DiscoveredDevice> = {}): DiscoveredDevice {
  return {
    id: "d1",
    name: "iPhone",
    ip: "192.168.1.10",
    port: 8420,
    platform: "ios",
    model: "iPhone 15",
    width: 390,
    height: 844,
    version: "1.0.0",
    lastSeen: Date.now(),
    ...overrides,
  };
}

function makeProgram(): Command {
  const program = new Command();
  program
    .name("kelpie")
    .option("--device <id>")
    .option("--format <type>", "Output format", "json")
    .option("--timeout <ms>", "Timeout", (v: string) => Number(v), 10000)
    .option("--port <port>", "Port", (v: string) => Number(v), 8420);
  registerGroup(program);
  return program;
}

describe("kelpie group <command> --allow-partial", () => {
  const originalFetch = globalThis.fetch;
  const originalExitCode = process.exitCode;
  let logSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    clearDevices();
    addDevice(makeDevice({ id: "d1", name: "iPhone" }));
    addDevice(makeDevice({ id: "d2", name: "Pixel", ip: "192.168.1.11" }));
    logSpy = vi.spyOn(console, "log").mockImplementation(() => undefined);
    process.exitCode = undefined;
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
    process.exitCode = originalExitCode;
    logSpy.mockRestore();
    clearDevices();
  });

  function mockMixedResults(): void {
    let call = 0;
    globalThis.fetch = vi.fn(async () => {
      call++;
      if (call === 2) {
        return new Response(
          JSON.stringify({ success: false, error: { code: "NAVIGATION_ERROR", message: "DNS failed" } }),
          { status: 502, headers: { "Content-Type": "application/json" } },
        );
      }
      return new Response(JSON.stringify({ success: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }) as typeof fetch;
  }

  it("surfaces per-device failures in output", async () => {
    mockMixedResults();
    const program = makeProgram();
    await program.parseAsync(["node", "kelpie", "group", "navigate", "https://example.com"]);

    const lastCall = logSpy.mock.calls[logSpy.mock.calls.length - 1]?.[0] as string;
    const printed = JSON.parse(lastCall) as {
      succeeded: number;
      failed: number;
      results: { success: boolean; error?: { code: string; message: string } }[];
    };
    expect(printed.succeeded).toBe(1);
    expect(printed.failed).toBe(1);
    const failure = printed.results.find((r) => !r.success);
    expect(failure?.error?.code).toBe("NAVIGATION_ERROR");
    expect(failure?.error?.message).toBe("DNS failed");
  });

  it("sets non-zero exit code by default when any device fails", async () => {
    mockMixedResults();
    const program = makeProgram();
    await program.parseAsync(["node", "kelpie", "group", "navigate", "https://example.com"]);
    expect(process.exitCode).toBe(1);
  });

  it("keeps exit code 0 with --allow-partial when some devices fail", async () => {
    mockMixedResults();
    const program = makeProgram();
    await program.parseAsync([
      "node",
      "kelpie",
      "group",
      "navigate",
      "https://example.com",
      "--allow-partial",
    ]);
    expect(process.exitCode).toBeFalsy();
  });

  it("keeps exit code 0 when every device succeeds, regardless of --allow-partial", async () => {
    globalThis.fetch = vi.fn(async () =>
      new Response(JSON.stringify({ success: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    ) as typeof fetch;

    const program = makeProgram();
    await program.parseAsync(["node", "kelpie", "group", "navigate", "https://example.com"]);
    expect(process.exitCode).toBeFalsy();
  });

  it("smart query: --allow-partial suppresses non-zero exit on device error", async () => {
    let call = 0;
    globalThis.fetch = vi.fn(async () => {
      call++;
      if (call === 1) {
        return new Response(JSON.stringify({ found: false }), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      }
      return new Response(
        JSON.stringify({ success: false, error: { code: "WEBVIEW_OFFLINE", message: "no view" } }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }) as typeof fetch;

    const program = makeProgram();
    await program.parseAsync([
      "node",
      "kelpie",
      "group",
      "find-button",
      "Submit",
      "--allow-partial",
    ]);
    expect(process.exitCode).toBeFalsy();
  });

  it("smart query: non-zero exit on device error without --allow-partial", async () => {
    let call = 0;
    globalThis.fetch = vi.fn(async () => {
      call++;
      if (call === 1) {
        return new Response(JSON.stringify({ found: false }), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      }
      return new Response(
        JSON.stringify({ success: false, error: { code: "WEBVIEW_OFFLINE", message: "no view" } }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }) as typeof fetch;

    const program = makeProgram();
    await program.parseAsync(["node", "kelpie", "group", "find-button", "Submit"]);
    expect(process.exitCode).toBe(1);
  });

  it("smart query: exit code unaffected by genuine 'not found' (no device errors)", async () => {
    globalThis.fetch = vi.fn(async () =>
      new Response(JSON.stringify({ found: false }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    ) as typeof fetch;

    const program = makeProgram();
    await program.parseAsync(["node", "kelpie", "group", "find-button", "Submit"]);
    expect(process.exitCode).toBeFalsy();
  });
});
