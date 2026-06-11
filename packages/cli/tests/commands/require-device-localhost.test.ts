import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { mkdtemp, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { Command } from "commander";
import { DEFAULT_PORT } from "@unlikeotherai/kelpie-shared";
import { requireDevice } from "../../src/commands/helpers.js";
import { clearDevices } from "../../src/discovery/registry.js";

// mDNS browse returns nothing; the localhost probe must self-heal.
vi.mock("../../src/discovery/scanner.js", () => ({
  scanForDevices: vi.fn(async () => []),
}));

function programWithoutDevice(): Command {
  const program = new Command();
  // requireDevice reads program.opts(); no --device is set so the auto-scan
  // path runs. A json format keeps any error output quiet/structured.
  program.setOptionValue("format", "json");
  return program;
}

describe("requireDevice localhost fallback", () => {
  const originalHome = process.env.HOME;
  let homeDir = "";

  beforeEach(async () => {
    clearDevices();
    homeDir = await mkdtemp(path.join(os.tmpdir(), "kelpie-require-device-"));
    process.env.HOME = homeDir;
  });

  afterEach(async () => {
    vi.unstubAllGlobals();
    process.env.HOME = originalHome;
    await rm(homeDir, { recursive: true, force: true });
  });

  it("falls back to a localhost device when the mDNS scan is empty", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string | URL | Request) => {
        const target = String(url);
        if (target.includes(`:${DEFAULT_PORT}/health`)) {
          return new Response("ok", { status: 200 });
        }
        throw new Error("connection refused");
      }),
    );

    const device = await requireDevice(programWithoutDevice());
    expect(device).not.toBeNull();
    expect(device?.ip).toBe("127.0.0.1");
    expect(device?.port).toBe(DEFAULT_PORT);
    expect(device?.id).toBe(`local:127.0.0.1:${DEFAULT_PORT}`);
  });

  it("returns NO_DEVICES when neither mDNS nor localhost respond", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        throw new Error("connection refused");
      }),
    );

    const device = await requireDevice(programWithoutDevice());
    expect(device).toBeNull();
    expect(process.exitCode).toBe(1);
    process.exitCode = 0;
  });
});
