import type { Page } from "playwright-core";
import { BrowserControlError } from "./protocol.js";
import { createWebMcpController } from "./webmcp.js";
import type { WebMcpController } from "./webmcp.js";
import { createIsolatedWebMcpPage } from "./isolated-webmcp.js";
import type { IsolatedWebMcpPage } from "./isolated-webmcp.js";
import { webMcpDiscoverParamsSchema } from "./webmcp-schema.js";
import type { WebMcpIdentity } from "./webmcp-schema.js";

export interface ManagedWebMcpPolicy {
  origins: readonly string[];
  inputEncoding: "json-string" | "object";
}
interface Entry {
  page: Page;
  realm: IsolatedWebMcpPage;
  available: boolean;
  controller: WebMcpController;
  loaded: () => void;
}
export interface ManagedWebMcpTabs {
  refresh(tabId: string): Promise<void>;
  controller(tabId: string, origin: string): Promise<WebMcpController>;
  ensureIdle(tabId: string): Promise<void>;
  forget(tabId: string): void;
}

/** One policy-bound controller per owned page; never enumerates a shared context. */
export function createManagedWebMcpTabs(input: {
  policy: ManagedWebMcpPolicy;
  sessionId: string;
  getPage(tabId: string): Promise<Page>;
  authorize(): Promise<void>;
  allowNavigation(url: URL): Promise<boolean> | boolean;
  availability(available: boolean): void;
}): ManagedWebMcpTabs {
  if (!["json-string", "object"].includes(input.policy.inputEncoding) || input.policy.origins.length > 100) {
    throw new BrowserControlError("INVALID_ARGUMENTS", "Invalid operator site tool policy.");
  }
  const origins = new Set(input.policy.origins.map(origin => webMcpDiscoverParamsSchema.parse({ origin }).origin));
  const inputEncoding = input.policy.inputEncoding;
  const entries = new Map<string, Entry>();
  const changed = (): void => { input.availability([...entries.values()].some(entry => entry.available)); };
  const entryFor = async (tabId: string): Promise<Entry> => {
    const page = await input.getPage(tabId);
    const old = entries.get(tabId);
    if (old) return old;
    const entry: Entry = {
      page, realm: createIsolatedWebMcpPage(page), available: false,
      loaded() { entry.available = false; changed(); },
      controller: createWebMcpController({
      inputEncoding,
      async identity() {
        await input.authorize();
        if (page.isClosed() || await input.getPage(tabId) !== page) throw new BrowserControlError("TAB_NOT_FOUND", "The site tool page is no longer owned.");
        return entry.realm.identity(input.sessionId);
      },
      async authorize(identity: WebMcpIdentity) {
        await input.authorize();
        const current = await entry.realm.identity(input.sessionId);
        if (identity.sessionId !== input.sessionId || identity.documentGeneration !== current.documentGeneration ||
            identity.origin !== current.origin || !origins.has(identity.origin) ||
            !await input.allowNavigation(new URL(identity.origin))) {
          throw new BrowserControlError("ACCESS_DENIED", "No operator grant covers this site tool document.");
        }
      },
      evaluate(operation) { return entry.realm.evaluate(operation); },
      // A URL/history/document epoch alone is not proof that an ignored callback
      // stopped. Closing this exact page is the supported confirmed retirement.
      isDocumentRetired() { return Promise.resolve(page.isClosed()); },
      }),
    };
    // DOMContentLoaded is a new-document observation checkpoint. It is deliberately
    // not used as execution-context teardown evidence for an uncertain invocation.
    page.on("domcontentloaded", entry.loaded);
    entries.set(tabId, entry);
    return entry;
  };
  const refresh = async (tabId: string): Promise<void> => {
    const entry = await entryFor(tabId);
    const origin = new URL(entry.page.url()).origin;
    const wasAvailable = entry.available;
    entry.available = false;
    if (origins.has(origin)) {
      try { entry.available = (await entry.controller.probe(origin)).available; }
      catch (error) {
        if (error instanceof BrowserControlError && error.code === "BUSY") entry.available = wasAvailable;
        // Navigation does not become successful WebMCP evidence on probe failure.
      }
    }
    changed();
  };
  return {
    refresh,
    async controller(tabId, origin) {
      if (!origins.has(origin)) throw new BrowserControlError("ACCESS_DENIED", "No operator grant covers this site tool origin.");
      const entry = await entryFor(tabId);
      await entry.controller.ensureIdle();
      if (!entry.available) await refresh(tabId);
      if (!entry.available) throw new BrowserControlError("UNSUPPORTED", "The actual browser site tool API is unavailable.");
      return entry.controller;
    },
    async ensureIdle(tabId) { await entries.get(tabId)?.controller.ensureIdle(); },
    forget(tabId) {
      const entry = entries.get(tabId);
      if (!entry) return;
      if (!entry.page.isClosed()) throw new BrowserControlError("BUSY", "Do not discard a live site tool renderer.");
      entries.delete(tabId);
      entry.page.off("domcontentloaded", entry.loaded);
      void entry.controller.dispose().finally(() => entry.realm.dispose()).catch(() => undefined);
      changed();
    },
  };
}
