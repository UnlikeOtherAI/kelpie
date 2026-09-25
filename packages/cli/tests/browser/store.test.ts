import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { chmod, mkdtemp, rm, symlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import {
  clearRunningBrowser,
  loadBrowserStore,
  removeBrowserAlias,
  setRunningBrowser,
  readLocalReadiness,
  upsertBrowserAlias,
} from "../../src/browser/store.js";

describe("browser store", () => {
  const originalHome = process.env.HOME;
  let homeDir = "";

  beforeEach(async () => {
    homeDir = await mkdtemp(path.join(os.tmpdir(), "kelpie-browser-store-"));
    process.env.HOME = homeDir;
  });

  afterEach(async () => {
    process.env.HOME = originalHome;
    await rm(homeDir, { recursive: true, force: true });
  });

  it("rejects readiness whose HTTP capability is not the literal boolean true", async () => {
    const file = path.join(homeDir, "readiness.json");
    await writeFile(file, JSON.stringify({
      version: 1, launchId: "launch", deviceId: "device", port: 8420,
      token: "a".repeat(32), controlMode: "loopback",
      mcp: { http: "true", stdio: false, endpoint: "/mcp" },
    }), { mode: 0o600 });
    await expect(readLocalReadiness(file)).resolves.toBeUndefined();
  });
  const capability = {
    version: 1, launchId: "launch", deviceId: "device", port: 8420,
    token: "a".repeat(32), controlMode: "loopback",
    mcp: { http: true, stdio: false, endpoint: "/mcp" },
  };
  it("reads a private regular readiness file", async () => {
    const file = path.join(homeDir, "readiness.json");
    await writeFile(file, JSON.stringify(capability), { mode: 0o600 });
    await expect(readLocalReadiness(file)).resolves.toEqual(capability);
    await expect(readLocalReadiness(homeDir)).resolves.toBeUndefined();
  });
  it.skipIf(process.platform === "win32")("rejects shared POSIX permissions and symlinks", async () => {
    const file = path.join(homeDir, "readiness.json");
    await writeFile(file, JSON.stringify(capability), { mode: 0o600 });
    await chmod(file, 0o644);
    await expect(readLocalReadiness(file)).resolves.toBeUndefined();
    await chmod(file, 0o600);
    const link = path.join(homeDir, "linked-readiness.json");
    await symlink(file, link);
    await expect(readLocalReadiness(link)).resolves.toBeUndefined();
  });
  it("persists aliases and running state under ~/.kelpie", async () => {
    await upsertBrowserAlias("claude-a", {
      platform: "macos",
      appPath: "/Applications/Kelpie.app",
    });
    await setRunningBrowser("claude-a", {
      port: 8427,
      lastLaunchedAt: "2026-04-01T09:00:00.000Z",
    });

    const store = await loadBrowserStore();
    expect(store.aliases["claude-a"]?.appPath).toBe("/Applications/Kelpie.app");
    expect(store.running["claude-a"]?.port).toBe(8427);
  });

  it("removes aliases and runtime state together", async () => {
    await upsertBrowserAlias("claude-a", { platform: "macos" });
    await setRunningBrowser("claude-a", {
      port: 8427,
      lastLaunchedAt: "2026-04-01T09:00:00.000Z",
    });

    await removeBrowserAlias("claude-a");
    const store = await loadBrowserStore();
    expect(store.aliases["claude-a"]).toBeUndefined();
    expect(store.running["claude-a"]).toBeUndefined();
  });

  it("clears runtime state without deleting alias configuration", async () => {
    await upsertBrowserAlias("claude-a", { platform: "macos" });
    await setRunningBrowser("claude-a", {
      port: 8427,
      lastLaunchedAt: "2026-04-01T09:00:00.000Z",
    });

    await clearRunningBrowser("claude-a");
    const store = await loadBrowserStore();
    expect(store.aliases["claude-a"]).toBeDefined();
    expect(store.running["claude-a"]).toBeUndefined();
  });
});
