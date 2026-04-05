import net from "node:net";
import { existsSync } from "node:fs";
import type { BrowserAlias } from "./store.js";
import { DEFAULT_PORT } from "@unlikeotherai/kelpie-shared";

const RESERVED_PORTS = new Set([8421]); // AppReveal + CLI MCP

export function validateBrowserName(name: string): boolean {
  return /^[a-zA-Z0-9_-]+$/.test(name);
}

export function resolveAppPath(alias: Pick<BrowserAlias, "platform" | "appPath">): string | null {
  const appPath = alias.appPath ?? (alias.platform === "macos" ? "/Applications/Kelpie.app" : null);
  if (!appPath) return null;
  return existsSync(appPath) ? appPath : null;
}

export async function allocateBrowserPort(requested?: number): Promise<number> {
  if (requested !== undefined) {
    if (RESERVED_PORTS.has(requested)) {
      throw new Error(`Port ${String(requested)} is reserved and cannot be used`);
    }
    return requested;
  }

  // Try DEFAULT_PORT first, then scan upward
  for (let port = DEFAULT_PORT; port < DEFAULT_PORT + 100; port++) {
    if (RESERVED_PORTS.has(port)) continue;
    if (await isPortFree(port)) return port;
  }
  throw new Error("No free port found in range");
}

function isPortFree(port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const server = net.createServer();
    server.once("error", () => { resolve(false); });
    server.once("listening", () => server.close(() => { resolve(true); }));
    server.listen(port, "127.0.0.1");
  });
}
