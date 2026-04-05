import os from "node:os";
import { access } from "node:fs/promises";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { DEFAULT_PORT } from "@unlikeotherai/kelpie-shared";
import type { Command } from "commander";
import { print } from "../output/formatter.js";
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

async function isReachable(port?: number): Promise<boolean> {
  if (!port) {
    return false;
  }
  try {
    const response = await fetch(`http://127.0.0.1:${String(port)}/health`);
    return response.ok;
  } catch {
    return false;
  }
}

function chooseLaunchPort(requestedPort?: string): number {
  if (requestedPort) {
    return Number(requestedPort);
  }
  return DEFAULT_PORT;
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
        await execFileAsync("open", ["-na", appPath, "--args", "--port", String(port)]);
        await setRunningBrowser(name, { port, lastLaunchedAt: new Date().toISOString() });
        print({ success: true, name, platform: alias.platform, appPath, port }, globals.format);
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
