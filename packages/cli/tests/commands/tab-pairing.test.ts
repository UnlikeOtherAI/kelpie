import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { setTokenStoreForTesting } from "../../src/auth/token-store.js";
import { addDevice, clearDevices } from "../../src/discovery/registry.js";
import { createProgram } from "../../src/program.js";

let directory: string;
beforeEach(async () => {
  directory = await mkdtemp(join(tmpdir(), "kelpie-tab-pairing-"));
  vi.stubEnv("KELPIE_HOME", directory);
  vi.stubEnv("KELPIE_UOA_ACCESS_TOKEN", undefined);
  addDevice({
    id: "unpaired", name: "Unpaired fixture", ip: "192.0.2.2", port: 8420,
    platform: "macos", model: "fixture", width: 0, height: 0, version: "test", lastSeen: Date.now(),
  });
});
afterEach(async () => {
  clearDevices();
  setTokenStoreForTesting(null);
  process.exitCode = undefined;
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  await rm(directory, { recursive: true, force: true });
});

it.each([
  ["screenshot", ["--tab-id", "owned-elsewhere", "screenshot", "--base64"]],
  ["screenshot-annotated", ["--tab-id", "owned-elsewhere", "annotate", "--base64"]],
  ["set-cookies", ["cookies", "import", "{fixture}", "--tab", "owned-elsewhere"]],
  ["copy-cookies", ["cookies", "copy", "--from-tab", "owned-elsewhere"]],
])("does not pair with a sole discovered device for untargeted %s", async (method, args) => {
  const file = join(directory, "cookies.json");
  await writeFile(file, JSON.stringify([{
    name: "fixture", value: "fixture", domain: "example.test", path: "/",
    expires: null, httpOnly: true, secure: true, sameSite: "Lax",
  }]));
  const fetch = vi.fn(async () => Response.json({ success: false, error: { code: "UNAUTHORIZED" } }, { status: 401 }));
  vi.stubGlobal("fetch", fetch);
  const output = vi.spyOn(console, "log").mockImplementation(() => undefined);

  await createProgram("test").parseAsync(["--format", "json", ...args.map((arg) => arg === "{fixture}" ? file : arg)], { from: "user" });

  expect(JSON.parse(output.mock.calls[0][0])).toMatchObject({ error: { code: "PAIR_TARGET_REQUIRED" } });
  expect(fetch).toHaveBeenCalledTimes(1);
  expect(fetch).toHaveBeenCalledWith(`http://192.0.2.2:8420/v1/${method}`, expect.anything());
});
