import { EventEmitter } from "node:events";
import { mkdtemp, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { waitForReadiness, type LaunchChild } from "../../src/commands/browser.js";

class FakeChild extends EventEmitter implements LaunchChild {
  exitCode: number | null = null;
}

describe("Windows browser readiness", () => {
  let tempDir = "";

  afterEach(async () => {
    if (tempDir) await rm(tempDir, { recursive: true, force: true });
  });

  it("reports an executable spawn error instead of leaving an unhandled child error", async () => {
    tempDir = await mkdtemp(path.join(os.tmpdir(), "kelpie-readiness-"));
    const child = new FakeChild();
    const waiting = waitForReadiness(path.join(tempDir, "readiness.json"), undefined, child, {
      timeoutMs: 1_000,
      pollMs: 1,
    });
    child.emit("error", new Error("ENOENT"));
    await expect(waiting).rejects.toThrow("Kelpie failed to start: ENOENT");
    expect(child.listenerCount("error")).toBe(0);
  });

  it("reports an early child exit before accepting stale readiness", async () => {
    tempDir = await mkdtemp(path.join(os.tmpdir(), "kelpie-readiness-"));
    const child = new FakeChild();
    child.exitCode = 23;
    await expect(waitForReadiness(path.join(tempDir, "readiness.json"), undefined, child)).rejects
      .toThrow("Kelpie exited before publishing readiness (exit 23)");
    expect(child.listenerCount("error")).toBe(0);
  });
});
