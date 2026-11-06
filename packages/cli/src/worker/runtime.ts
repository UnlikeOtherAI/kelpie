import { randomUUID } from "node:crypto";
import { chromium } from "playwright-core";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { BrowserControlError } from "@unlikeotherai/kelpie-shared/browser-control";
import { createManagedSessionRegistry } from "../browser/automation-sessions.js";
import { createWorkerMcpServer } from "./mcp.js";
import { loadWorkerConfig, workerEndpoint } from "./config.js";
import { createWorkerSessionAllocator } from "./allocation.js";
import { closeWorkerTransportOnEof, reportWorkerCleanupFailure } from "./stdio-eof.js";

/** Explicit operator launch authorizes one local stdio principal, not a new human account. */
export async function startWorkerMcp(path: string, version: string): Promise<void> {
  const config = await loadWorkerConfig(path);
  let browser;
  try { browser = await chromium.connectOverCDP(workerEndpoint(config), { timeout: 10_000 }); }
  catch { throw new Error("The configured worker connection failed."); }
  const owner = "stdio:" + randomUUID();
  let closed = false;
  const authorize = (): void => { if (closed) throw new BrowserControlError("SESSION_CLOSED", "The worker transport is closed."); };
  const allocation = createWorkerSessionAllocator(browser, config, owner, authorize);
  const registry = createManagedSessionRegistry({ owner, authorize, maxSessions: config.maxSessions, allocate: options => allocation.allocate(options) });
  const server = createWorkerMcpServer(registry, version);
  let stopping: Promise<void> | undefined;
  const shutdown = (): Promise<void> => {
    if (stopping) return stopping;
    closed = true;
    stopping = (async () => {
      let failed = false;
      try { await registry.dispose(); } catch { failed = true; }
      try { await allocation.closeSharedContext(); } catch { failed = true; }
      // Pinned Playwright's CDP browserProcess.close disconnects its transport;
      // it does not send Browser.close or terminate the borrowed external browser.
      try { await browser.close(); } catch { failed = true; }
      if (failed) throw new BrowserControlError("CLEANUP_FAILED", "Some worker resources could not be closed.");
    })();
    return stopping;
  };
  const transport = new StdioServerTransport();
  const detachInputEnd = closeWorkerTransportOnEof(process.stdin, transport, () => {
    reportWorkerCleanupFailure();
    void shutdown().catch(reportWorkerCleanupFailure);
  });
  server.server.onclose = () => { detachInputEnd(); void shutdown().catch(reportWorkerCleanupFailure); };
  const onSignal = (): void => { void shutdown().then(() => process.exit(process.exitCode ? 1 : 0), () => { reportWorkerCleanupFailure(); process.exit(1); }); };
  process.once("SIGINT", onSignal);
  process.once("SIGTERM", onSignal);
  try { await server.connect(transport); }
  catch {
    detachInputEnd();
    await shutdown().catch(() => undefined);
    throw new Error("The worker stdio transport could not start.");
  }
}
