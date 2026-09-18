import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { addDevice, clearDevices } from "../../src/discovery/registry.js";
import { createProgram } from "../../src/program.js";
import {
  partitionFlagError,
  partitionTabBody,
} from "../../src/commands/partition-options.js";
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

function fetchMock(): ReturnType<typeof vi.fn> {
  return globalThis.fetch as ReturnType<typeof vi.fn>;
}

function capturedUrl(): string {
  return fetchMock().mock.calls[0]?.[0] as string;
}

function capturedBody(): Record<string, unknown> | undefined {
  const init = fetchMock().mock.calls[0]?.[1] as RequestInit | undefined;
  return init?.body ? JSON.parse(init.body as string) : undefined;
}

function makeProgram() {
  const program = createProgram("0.0.0-test");
  program.exitOverride();
  program.configureOutput({ writeOut: () => undefined, writeErr: () => undefined });
  return program;
}

async function run(...args: string[]): Promise<void> {
  await makeProgram().parseAsync(["node", "kelpie", ...args, "--device", "test-device"]);
}

describe("partition flag validation", () => {
  it("accepts a bare --partition", () => {
    expect(partitionFlagError({ partition: "sam.eng-lead" })).toBeNull();
  });

  it("accepts no partition flags at all", () => {
    expect(partitionFlagError({})).toBeNull();
  });

  it("rejects --ephemeral without --partition", () => {
    expect(partitionFlagError({ ephemeral: true })).toContain("--ephemeral requires --partition");
  });

  it("rejects --non-persistent without --partition", () => {
    expect(partitionFlagError({ nonPersistent: true })).toContain("--ephemeral requires --partition");
  });

  it("accepts --ephemeral alongside --partition", () => {
    expect(partitionFlagError({ partition: "throwaway", ephemeral: true })).toBeNull();
  });

  it("rejects a partition that fails the shared validator", () => {
    expect(partitionFlagError({ partition: "default" })).toContain("invalid --partition");
    expect(partitionFlagError({ partition: "has space" })).toContain("invalid --partition");
    expect(partitionFlagError({ partition: "ephemeral-x" })).toContain("invalid --partition");
    expect(partitionFlagError({ partition: "" })).toContain("invalid --partition");
  });

  it("rejects a name longer than 200 characters", () => {
    expect(partitionFlagError({ name: "x".repeat(201) })).toContain("--name");
    expect(partitionFlagError({ name: "x".repeat(200) })).toBeNull();
  });
});

describe("partition request body", () => {
  it("stays empty when no flags are supplied, preserving today's wire format", () => {
    expect(partitionTabBody({})).toEqual({});
  });

  it("omits persistent unless it is explicitly turned off", () => {
    expect(partitionTabBody({ partition: "sam" })).toEqual({ partition: "sam" });
  });

  it("sends persistent:false for --ephemeral", () => {
    expect(partitionTabBody({ partition: "sam", ephemeral: true })).toEqual({
      partition: "sam",
      persistent: false,
    });
  });

  it("treats --non-persistent as an alias for --ephemeral", () => {
    expect(partitionTabBody({ partition: "sam", nonPersistent: true })).toEqual({
      partition: "sam",
      persistent: false,
    });
  });

  it("carries an empty name through rather than dropping it", () => {
    expect(partitionTabBody({ name: "" })).toEqual({ name: "" });
  });
});

describe("partition commands over the wire", () => {
  const originalFetch = globalThis.fetch;

  beforeEach(() => {
    clearDevices();
    addDevice(device);
    process.exitCode = undefined;
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
    clearDevices();
    process.exitCode = undefined;
    vi.restoreAllMocks();
  });

  it("tab new carries name, partition and persistent into the body", async () => {
    mockFetch({ success: true });
    await run("tab", "new", "https://example.com/", "--name", "Sam (Eng Lead)", "--partition", "sam.eng-lead", "--ephemeral");

    expect(capturedUrl()).toBe("http://192.168.1.42:8420/v1/new-tab");
    expect(capturedBody()).toEqual({
      url: "https://example.com/",
      name: "Sam (Eng Lead)",
      partition: "sam.eng-lead",
      persistent: false,
    });
  });

  it("tab new without the new flags sends exactly what it always did", async () => {
    mockFetch({ success: true });
    await run("tab", "new", "https://example.com/");

    expect(capturedBody()).toEqual({ url: "https://example.com/" });
  });

  it("tab new refuses an invalid partition without sending a request", async () => {
    mockFetch({ success: true });
    await run("tab", "new", "--partition", "Default");

    expect(fetchMock()).not.toHaveBeenCalled();
    expect(process.exitCode).toBe(1);
  });

  it("tab new refuses --ephemeral without --partition without sending a request", async () => {
    mockFetch({ success: true });
    await run("tab", "new", "--ephemeral");

    expect(fetchMock()).not.toHaveBeenCalled();
    expect(process.exitCode).toBe(1);
  });

  it("partitions maps to POST /v1/get-partitions", async () => {
    mockFetch({ success: true, partitions: [] });
    await run("partitions");

    // Sends no body at all, like every other parameterless command (`tabs`);
    // the endpoint treats a missing body and `{}` identically.
    expect(capturedUrl()).toBe("http://192.168.1.42:8420/v1/get-partitions");
    expect(capturedBody()).toBeUndefined();
  });

  it("partition delete maps to POST /v1/delete-partition with the id", async () => {
    mockFetch({ success: true, deleted: "sam.eng-lead", tabsClosed: 2, existed: true });
    await run("partition", "delete", "sam.eng-lead");

    expect(capturedUrl()).toBe("http://192.168.1.42:8420/v1/delete-partition");
    expect(capturedBody()).toEqual({ id: "sam.eng-lead" });
  });

  it("partition delete rejects an invalid id before sending a request", async () => {
    mockFetch({ success: true });
    await run("partition", "delete", "..");

    expect(fetchMock()).not.toHaveBeenCalled();
    expect(process.exitCode).toBe(1);
  });
});
