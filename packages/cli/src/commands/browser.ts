import os from "node:os";
import { access } from "node:fs/promises";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { DEFAULT_PORT } from "@unlikeotherai/kelpie-shared";
import type { Command } from "commander";
import { print } from "../output/formatter.js";
import { probeHealth } from "../discovery/local-probe.js";
import type { GlobalOptions } from "../types.js";
import {
  clearRunningBrowser,
  getBrowserAlias,
  loadBrowserStore,
  removeBrowserAlias,
  setRunningBrowser,
  upsertBrowserAlias,
} from "../browser/store.js";

const execFileAsync = promisify(execFile);

/** How many ports above the requested one the macOS app may fall back to. */
const PORT_FALLBACK_RANGE = 10;
/** How long to wait for a freshly launched instance to bind a port. */
const LAUNCH_BIND_TIMEOUT_MS = 12_000;
/** How often to re-probe while waiting for the launched instance to bind. */
const LAUNCH_BIND_POLL_MS = 400;

async function isReachable(port?: number): Promise<boolean> {
  if (!port) {
    return false;
  }
  return probeHealth(port);
}

function chooseLaunchPort(requestedPort?: string): number {
  if (requestedPort) {
    return Number(requestedPort);
  }
  return DEFAULT_PORT;
}

function fallbackPorts(requestedPort: number): number[] {
  return Array.from({ length: PORT_FALLBACK_RANGE }, (_value, index) => requestedPort + index);
}

/** Ports in the fallback range already reachable before launch (stale instances). */
async function reachablePorts(ports: number[]): Promise<Set<number>> {
  const checks = await Promise.all(
    ports.map(async (port) => ({ port, reachable: await probeHealth(port) })),
  );
  return new Set(checks.filter((check) => check.reachable).map((check) => check.port));
}

const delay = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * The macOS app falls back to the next free port when the requested one is held
 * by a stale instance. Poll the fallback range for a port that became reachable
 * after launch (i.e. was not reachable before) so the store records the real
 * bound port. Prefer the requested port when it newly comes up.
 */
async function waitForBoundPort(
  requestedPort: number,
  preLaunchReachable: Set<number>,
): Promise<number | undefined> {
  const ports = fallbackPorts(requestedPort);
  const deadline = Date.now() + LAUNCH_BIND_TIMEOUT_MS;
  while (Date.now() < deadline) {
    const nowReachable = await reachablePorts(ports);
    const fresh = ports.filter((port) => nowReachable.has(port) && !preLaunchReachable.has(port));
    if (fresh.includes(requestedPort)) {
      return requestedPort;
    }
    if (fresh.length > 0) {
      return fresh[0];
    }
    await delay(LAUNCH_BIND_POLL_MS);
  }
  return undefined;
}

export function registerBrowser(program: Command): void {
  const browser = program.command("browser").description("Manage local browser aliases");

  browser
    .command("register <name>")
    .option("--platform <platform>", "Alias platform", os.platform() === "darwin" ? "macos" : "linux")
    .option("--app-path <path>", "Explicit app path")
    .action(async (name: string, opts: { platform: "macos" | "linux" | "windows"; appPath?: string }) => {
      const globals = program.opts<GlobalOptions>();
      await upsertBrowserAlias(name, { platform: opts.platform, appPath: opts.appPath });
      print({ success: true, name, platform: opts.platform, appPath: opts.appPath ?? null }, globals.format);
    });

  browser
    .command("list")
    .action(async () => {
      const globals = program.opts<GlobalOptions>();
      const store = await loadBrowserStore();
      const browsers = await Promise.all(
        Object.entries(store.aliases).map(async ([name, alias]) => {
          const running = store.running[name];
          return {
            name,
            platform: alias.platform,
            appPath: alias.appPath ?? "",
            port: running?.port ?? "",
            lastLaunchedAt: running?.lastLaunchedAt ?? "",
            reachable: await isReachable(running?.port),
          };
        }),
      );
      print({ browsers }, globals.format);
    });

  browser
    .command("inspect <name>")
    .action(async (name: string) => {
      const globals = program.opts<GlobalOptions>();
      const store = await loadBrowserStore();
      const alias = store.aliases[name];
      if (!alias) {
        print({ success: false, error: { code: "BROWSER_NOT_REGISTERED", message: `No browser alias named "${name}"` } }, globals.format);
        process.exitCode = 4;
        return;
      }
      const running = store.running[name];
      print({
        name,
        platform: alias.platform,
        appPath: alias.appPath ?? null,
        port: running?.port ?? null,
        lastLaunchedAt: running?.lastLaunchedAt ?? null,
        reachable: await isReachable(running?.port),
      }, globals.format);
    });

  browser
    .command("remove <name>")
    .action(async (name: string) => {
      const globals = program.opts<GlobalOptions>();
      await removeBrowserAlias(name);
      print({ success: true, removed: name }, globals.format);
    });

  browser
    .command("launch <name>")
    .option("--port <port>", "Port to use for the launched browser")
    .action(async (name: string, opts: { port?: string }) => {
      const globals = program.opts<GlobalOptions>();
      const alias = await getBrowserAlias(name);
      if (!alias) {
        print({ success: false, error: { code: "BROWSER_NOT_REGISTERED", message: `No browser alias named "${name}"` } }, globals.format);
        process.exitCode = 4;
        return;
      }

      const port = chooseLaunchPort(opts.port);
      if (alias.platform !== "macos") {
        await setRunningBrowser(name, { port, lastLaunchedAt: new Date().toISOString() });
        print({
          success: true,
          name,
          platform: alias.platform,
          port,
          note: "Recorded local browser alias without spawning a new process on this platform.",
        }, globals.format);
        return;
      }

      const appPath = alias.appPath ?? "/Applications/Kelpie.app";
      try {
        await access(appPath);
      } catch {
        print({ success: false, error: { code: "APP_NOT_INSTALLED", message: `App not found at ${appPath}` } }, globals.format);
        process.exitCode = 5;
        return;
      }

      try {
        const preLaunchReachable = await reachablePorts(fallbackPorts(port));
        await execFileAsync("open", ["-na", appPath, "--args", "--port", String(port)]);
        const boundPort = (await waitForBoundPort(port, preLaunchReachable)) ?? port;
        await setRunningBrowser(name, { port: boundPort, lastLaunchedAt: new Date().toISOString() });
        print({ success: true, name, platform: alias.platform, appPath, port: boundPort }, globals.format);
      } catch (error) {
        await clearRunningBrowser(name);
        print({
          success: false,
          error: {
            code: "BROWSER_LAUNCH_FAILED",
            message: error instanceof Error ? error.message : "Failed to launch browser",
          },
        }, globals.format);
        process.exitCode = 6;
      }
    });
}
