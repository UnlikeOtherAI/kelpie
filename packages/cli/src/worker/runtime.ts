import { randomUUID } from "node:crypto";
import { chromium } from "playwright-core";
import type { BrowserContext } from "playwright-core";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { allocateManagedBrowserSession, BrowserControlError } from "@unlikeotherai/kelpie-shared/browser-control";
import { createManagedSessionRegistry } from "../browser/automation-sessions.js";
import { createWorkerMcpServer } from "./mcp.js";
import { loadWorkerConfig, workerEndpoint } from "./config.js";

/** Explicit operator launch authorizes one local stdio principal, not a new human account. */
export async function startWorkerMcp(path: string): Promise<void> {
  const config = await loadWorkerConfig(path);
  let browser;
  try { browser = await chromium.connectOverCDP(workerEndpoint(config), { timeout: 10_000 }); }
  catch { throw new Error("The configured worker connection failed."); }
  const owner = "stdio:" + randomUUID();
  let closed = false;
  let sharedContext: Promise<BrowserContext> | undefined;
  const authorize = (): void => { if (closed) throw new BrowserControlError("SESSION_CLOSED", "The worker transport is closed."); };
  const origins = new Set(config.allowedOrigins);
  const registry = createManagedSessionRegistry({
    owner, authorize, maxSessions: config.maxSessions,
    async allocate(options) {
      const ttlMs = options.ttlMs ?? Math.min(300_000, config.maxTtlMs);
      if (ttlMs > config.maxTtlMs) throw new BrowserControlError("RESOURCE_LIMIT", "The session duration exceeds the operator limit.");
      if (options.isolation === "shared" && !sharedContext) {
        sharedContext = browser.newContext({ serviceWorkers: "block", acceptDownloads: false });
        void sharedContext.catch(() => { sharedContext = undefined; });
      }
      return allocateManagedBrowserSession({
        browser, backend: config.backend, owner, authorize, options: { ...options, ttlMs },
        sharedContext: options.isolation === "shared" ? await sharedContext : undefined,
        maxTabs: config.maxTabs, verifiedLightpandaMethods: config.verifiedLightpandaMethods,
        network: { boundary: config.networkBoundary, allowNavigation: (url) => origins.has(url.origin) },
      });
    },
  });
  const server = createWorkerMcpServer(registry);
  let stopping: Promise<void> | undefined;
  const shutdown = (): Promise<void> => {
    if (stopping) return stopping;
    closed = true;
    stopping = (async () => {
      let failed = false;
      try { await registry.dispose(); } catch { failed = true; }
      try { if (sharedContext) await (await sharedContext).close(); } catch { failed = true; }
      // Pinned Playwright's CDP browserProcess.close disconnects its transport;
      // it does not send Browser.close or terminate the borrowed external browser.
      try { await browser.close(); } catch { failed = true; }
      if (failed) throw new BrowserControlError("CLEANUP_FAILED", "Some worker resources could not be closed.");
    })();
    return stopping;
  };
  server.server.onclose = () => { void shutdown().catch(() => { process.stderr.write("Worker cleanup failed.\n"); }); };
  const onSignal = (): void => { void shutdown().then(() => process.exit(0), () => { process.stderr.write("Worker cleanup failed.\n"); process.exit(1); }); };
  process.once("SIGINT", onSignal);
  process.once("SIGTERM", onSignal);
  try { await server.connect(new StdioServerTransport()); }
  catch {
    await shutdown().catch(() => undefined);
    throw new Error("The worker stdio transport could not start.");
  }
}
