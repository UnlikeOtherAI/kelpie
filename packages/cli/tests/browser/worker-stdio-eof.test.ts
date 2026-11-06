import { PassThrough } from "node:stream";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { describe, expect, it, vi } from "vitest";
import { closeWorkerTransportOnEof, reportWorkerCleanupFailure } from "../../src/worker/stdio-eof.js";

describe("worker stdio EOF", () => {
  it("closes the actual pinned server transport on input EOF", async () => {
    const input = new PassThrough();
    const output = new PassThrough();
    const transport = new StdioServerTransport(input, output);
    const failure = vi.fn();
    let resolveClosed!: () => void;
    const closed = new Promise<void>((resolve) => { resolveClosed = resolve; });
    const onClose = vi.fn(() => { resolveClosed(); });
    transport.onclose = onClose;
    const detach = closeWorkerTransportOnEof(input, transport, failure);
    await transport.start();
    input.end();
    await closed;
    input.emit("end");
    await Promise.resolve();
    expect(onClose).toHaveBeenCalledOnce();
    expect(failure).not.toHaveBeenCalled();
    detach();
  });

  it("routes transport-close failure to cleanup and supports detaching", async () => {
    const input = new PassThrough();
    const failure = vi.fn();
    const transport = { close: vi.fn(async () => { throw new Error("close"); }) };
    const detach = closeWorkerTransportOnEof(input, transport, failure);
    input.emit("end");
    await vi.waitFor(() => { expect(failure).toHaveBeenCalledOnce(); });
    detach();
    const detached = new PassThrough();
    const stop = closeWorkerTransportOnEof(detached, transport, failure);
    stop();
    detached.emit("end");
    expect(transport.close).toHaveBeenCalledOnce();
  });

  it("marks cleanup failure as a nonzero process exit", () => {
    const prior = process.exitCode;
    const stderr = vi.spyOn(process.stderr, "write").mockImplementation(() => true);
    try {
      reportWorkerCleanupFailure();
      expect(process.exitCode).toBe(1);
      expect(stderr).toHaveBeenCalledOnce();
    } finally {
      process.exitCode = prior;
      stderr.mockRestore();
    }
  });
});
