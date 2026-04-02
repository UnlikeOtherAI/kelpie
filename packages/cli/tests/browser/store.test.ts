import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { mkdtemp, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import {
  clearRunningBrowser,
  loadBrowserStore,
  removeBrowserAlias,
  setRunningBrowser,
  upsertBrowserAlias,
} from "../../src/browser/store.js";

describe("browser store", () => {
  const originalHome = process.env.HOME;
  let homeDir = "";

  beforeEach(async () => {
    homeDir = await mkdtemp(path.join(os.tmpdir(), "mollotov-browser-store-"));
    process.env.HOME = homeDir;
  });

  afterEach(async () => {
    process.env.HOME = originalHome;
    await rm(homeDir, { recursive: true, force: true });
  });

  it("persists aliases and running state under ~/.mollotov", async () => {
    await upsertBrowserAlias("claude-a", {
      platform: "macos",
      appPath: "/Applications/Mollotov.app",
    });
    await setRunningBrowser("claude-a", {
      port: 8427,
      lastLaunchedAt: "2026-04-01T09:00:00.000Z",
    });

    const store = await loadBrowserStore();
    expect(store.aliases["claude-a"]?.appPath).toBe("/Applications/Mollotov.app");
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
