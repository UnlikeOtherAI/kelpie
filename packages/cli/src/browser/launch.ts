import net from "node:net";
import { existsSync } from "node:fs";
import type { BrowserAlias } from "./store.js";
import { DEFAULT_PORT } from "@unlikeotherai/kelpie-shared";

const RESERVED_PORTS = new Set([8421]); // AppReveal + CLI MCP
/** How far above DEFAULT_PORT automatic allocation looks for a free port. */
const ALLOCATION_RANGE = 100;

export function validateBrowserName(name: string): boolean {
  return /^[a-zA-Z0-9_-]+$/.test(name);
}

export function resolveAppPath(alias: Pick<BrowserAlias, "platform" | "appPath">): string | null {
  const appPath = alias.appPath ?? (alias.platform === "macos" ? "/Applications/Kelpie.app" : null);
  if (!appPath) return null;
  return existsSync(appPath) ? appPath : null;
}

/**
 * The port `browser launch` uses when none was given: the first free one from
 * DEFAULT_PORT upward, skipping the reserved ones. The Windows app fails its
 * startup on an occupied port rather than moving, so the CLI has to hand it a
 * free one; the macOS app's own fallback stays behind this as a safety net.
 * Two launches started at the same moment can still pick the same port.
 */
export async function allocateBrowserPort(
  isFree: (port: number) => Promise<boolean> = isPortFree,
): Promise<number> {
  for (let port = DEFAULT_PORT; port < DEFAULT_PORT + ALLOCATION_RANGE; port++) {
    if (RESERVED_PORTS.has(port)) continue;
    if (await isFree(port)) return port;
  }
  throw new Error(`No free port from ${DEFAULT_PORT} to ${DEFAULT_PORT + ALLOCATION_RANGE - 1}`);
}

/** Whether `port` can be bound on 127.0.0.1, the address the Windows app binds. */
export function isPortFree(port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const server = net.createServer();
    server.once("error", () => { resolve(false); });
    server.once("listening", () => server.close(() => { resolve(true); }));
    server.listen(port, "127.0.0.1");
  });
}
