import type { Browser, BrowserContext } from "playwright-core";
import type { AutomationSessionOptions } from "@unlikeotherai/kelpie-shared";
import { allocateManagedBrowserSession, BrowserControlError } from "@unlikeotherai/kelpie-shared/browser-control";
import type { WorkerConfig } from "./config.js";

/** Owns only the automation context created for explicit shared storage. */
export function createWorkerSessionAllocator(browser: Browser, config: WorkerConfig, owner: string, authorize: () => void) {
  let sharedContext: Promise<BrowserContext> | undefined;
  const origins = new Set(config.allowedOrigins);
  return {
    async allocate(options: AutomationSessionOptions) {
      if (config.backend === "lightpanda" && options.isolation === "shared") {
        throw new BrowserControlError("ISOLATION_UNAVAILABLE", "Shared storage is not verified for this restricted worker.");
      }
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
        webMcp: config.webMcpInputEncoding && config.webMcpOrigins.length ? { origins: config.webMcpOrigins, inputEncoding: config.webMcpInputEncoding } : undefined,
        network: { boundary: config.networkBoundary, allowNavigation: url => origins.has(url.origin) },
      });
    },
    async closeSharedContext(): Promise<void> {
      if (sharedContext) {
        await (await sharedContext).close();
        sharedContext = undefined;
      }
    },
  };
}
