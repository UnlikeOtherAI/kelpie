import { once } from "node:events";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";

const control = vi.hoisted(() => ({ child: undefined as import("node:child_process").ChildProcess | undefined, exitsEarly: false, refuseKill: false }));
vi.mock("node:child_process", async (importOriginal) => {
  const actual = await importOriginal<typeof import("node:child_process")>();
  return { ...actual, spawn: () => {
    control.child = actual.spawn(process.execPath, ["-e", control.exitsEarly ? "process.exit(23)" : control.refuseKill ? "setTimeout(() => {}, 14000)" : "setInterval(() => {}, 1000)"], { stdio: "ignore" });
    if (control.refuseKill) vi.spyOn(control.child, "kill").mockReturnValue(false);
    return control.child;
  } };
});
import { createProgram } from "../../src/program.js";
import { clearRunningBrowserIfMatches, loadBrowserStore, setRunningBrowser } from "../../src/browser/store.js";

describe("public browser launch child lifecycle", () => {
  let home = "";
  const oldHome = process.env.KELPIE_HOME;
  const run = (...args: string[]) => createProgram("test").parseAsync(["node", "kelpie", ...args]);
  afterEach(async () => {
    if (oldHome === undefined) delete process.env.KELPIE_HOME; else process.env.KELPIE_HOME = oldHome;
    process.exitCode = undefined;
    control.refuseKill = false; control.exitsEarly = false;
    vi.restoreAllMocks();
    if (home) await rm(home, { recursive: true, force: true });
  });

  it("retires the real unready child, clears the pending record and permits retry", async () => {
    home = await mkdtemp(path.join(os.tmpdir(), "kelpie-launch-owned-"));
    process.env.KELPIE_HOME = home;
    vi.spyOn(console, "log").mockImplementation(() => undefined);
    const profile = path.join(home, "profile");
    await run("browser", "register", "owned", "--platform", "windows", "--app-path", process.execPath, "--profile-dir", profile);
    control.exitsEarly = false;
    await run("browser", "launch", "owned", "--port", "28423");
    const first = control.child!;
    expect(first.exitCode !== null || first.signalCode !== null).toBe(true);
    expect((await loadBrowserStore()).running.owned).toBeUndefined();
    process.exitCode = undefined;
    control.exitsEarly = true;
    await run("browser", "launch", "owned", "--port", "28423");
    expect(control.child).not.toBe(first);
    expect(control.child!.exitCode).toBe(23);
    expect((await loadBrowserStore()).running.owned).toBeUndefined();
  }, 30000);

  it("retains a refused child until it exits and self-heals on retry", async () => {
    home = await mkdtemp(path.join(os.tmpdir(), "kelpie-launch-recovery-"));
    process.env.KELPIE_HOME = home;
    vi.spyOn(console, "log").mockImplementation(() => undefined);
    const profile = path.join(home, "profile");
    await run("browser", "register", "owned", "--platform", "windows", "--app-path", process.execPath, "--profile-dir", profile);
    control.exitsEarly = false; control.refuseKill = true;
    await run("browser", "launch", "owned", "--port", "28423");
    const child = control.child!;
    const pending = (await loadBrowserStore()).running.owned;
    expect(pending?.pid).toBe(child.pid);
    expect(pending?.pendingLaunch?.profileDir).toBe(profile);
    expect(child.exitCode).toBeNull();
    await once(child, "exit");
    control.refuseKill = false; control.exitsEarly = true; process.exitCode = undefined;
    await run("browser", "launch", "owned", "--port", "28423");
    expect(control.child).not.toBe(child);
    expect((await loadBrowserStore()).running.owned).toBeUndefined();
  }, 30000);
  it("reconciles an absent pending PID before register and remove", async () => {
    home = await mkdtemp(path.join(os.tmpdir(), "kelpie-launch-dead-"));
    process.env.KELPIE_HOME = home;
    vi.spyOn(console, "log").mockImplementation(() => undefined);
    const profile = path.join(home, "profile");
    await run("browser", "register", "owned", "--platform", "windows", "--app-path", process.execPath, "--profile-dir", profile);
    control.exitsEarly = true;
    const { spawn } = await import("node:child_process");
    const child = spawn(process.execPath, []);
    await once(child, "exit");
    const pending = { port: 28423, lastLaunchedAt: "now", pid: child.pid, readinessFile: path.join(profile, "readiness.json"),
      pendingLaunch: { attemptId: "attempt", appPath: process.execPath, profileDir: profile, startedAt: "now" } };
    await setRunningBrowser("owned", pending);
    await run("browser", "register", "owned", "--platform", "windows", "--app-path", process.execPath, "--profile-dir", profile);
    expect((await loadBrowserStore()).running.owned).toBeUndefined();
    await setRunningBrowser("owned", pending);
    await run("browser", "remove", "owned");
    const store = await loadBrowserStore();
    expect(store.running.owned).toBeUndefined();
    expect(store.aliases.owned).toBeUndefined();
  });
  it("reconciles a dead launch without deleting readiness and refuses changed identity", async () => {
    home = await mkdtemp(path.join(os.tmpdir(), "kelpie-launch-stale-"));
    process.env.KELPIE_HOME = home;
    vi.spyOn(console, "log").mockImplementation(() => undefined);
    const profile = path.join(home, "profile"), readinessFile = path.join(profile, "readiness.json");
    await mkdir(profile);
    await run("browser", "register", "owned", "--platform", "windows", "--app-path", process.execPath, "--profile-dir", profile);
    control.exitsEarly = true;
    const { spawn } = await import("node:child_process");
    const child = spawn(process.execPath, []); await once(child, "exit");
    const running = { port: 28423, lastLaunchedAt: "now", pid: child.pid, launchId: "launch-a", readinessFile };
    await writeFile(readinessFile, JSON.stringify({ version: 1, launchId: "launch-a", deviceId: "device-a", port: 28423,
      token: "a".repeat(32), controlMode: "loopback", mcp: { http: true, stdio: false, endpoint: "/mcp" } }), { mode: 0o600 });
    await setRunningBrowser("owned", { ...running, launchId: "replacement" });
    expect(await clearRunningBrowserIfMatches("owned", running)).toBe(false);
    expect((await loadBrowserStore()).running.owned.launchId).toBe("replacement");
    await setRunningBrowser("owned", { ...running, launchId: "other" });
    await run("browser", "stop", "owned");
    expect((await loadBrowserStore()).running.owned.launchId).toBe("other");
    process.exitCode = undefined;
    await setRunningBrowser("owned", running);
    await run("browser", "stop", "owned");
    expect((await loadBrowserStore()).running.owned).toBeUndefined();
    expect(JSON.parse(await readFile(readinessFile, "utf8")).launchId).toBe("launch-a");
    await rm(readinessFile);
    await setRunningBrowser("owned", running);
    await run("browser", "stop", "owned");
    expect((await loadBrowserStore()).running.owned).toBeUndefined();
  });
  it("keeps a pending live PID and does not replace or kill it", async () => {
    home = await mkdtemp(path.join(os.tmpdir(), "kelpie-launch-pending-"));
    process.env.KELPIE_HOME = home;
    vi.spyOn(console, "log").mockImplementation(() => undefined);
    const profile = path.join(home, "profile");
    await run("browser", "register", "owned", "--platform", "windows", "--app-path", process.execPath, "--profile-dir", profile);
    await setRunningBrowser("owned", { port: 28423, lastLaunchedAt: "now", pid: process.pid, readinessFile: path.join(profile, "readiness.json"),
      pendingLaunch: { attemptId: "attempt", appPath: process.execPath, profileDir: profile, startedAt: "now" } });
    control.child = undefined;
    await run("browser", "launch", "owned", "--port", "28423");
    expect(control.child).toBeUndefined();
    expect((await loadBrowserStore()).running.owned?.pendingLaunch?.attemptId).toBe("attempt");
    expect(process.exitCode).toBe(6);
  });
});