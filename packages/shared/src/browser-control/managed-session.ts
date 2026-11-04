import type { Browser, BrowserContext, Page } from "playwright-core";
import { BrowserControlError, browserControlMutates } from "./protocol.js";
import type { BrowserControlBackend, BrowserControlRequest, BrowserControlTransport, BrowserTabInfo } from "./protocol.js";
import { createPlaywrightBrowserBackend } from "./playwright.js";
import { createBrowserControlProxy } from "./proxy.js";
import type { PlaywrightBrowserBinding } from "./playwright.js";
import { createLightpandaBrowserBackend } from "./lightpanda.js";
import type { LightpandaVerifiedMethod } from "./lightpanda.js";
import { automationSessionOptionsSchema } from "../automation-session.js";
import type { AutomationSessionDescription, AutomationSessionOptions } from "../automation-session.js";

export interface ManagedBrowserSessionOptions {
  /** Already connected by trusted application code. No model-supplied endpoint. */
  browser: Browser;
  backend: "playwright" | "lightpanda";
  owner: string;
  authorize(owner: string): Promise<void> | void;
  options: AutomationSessionOptions;
  /** Required only for explicit shared storage. Existing pages are never imported. */
  sharedContext?: BrowserContext;
  maxTabs?: number;
  /**
   * Requested top-level URL policy only. The operator must separately constrain worker
   * egress/resources: this callback cannot police subresources or DNS rebinding.
   */
  network: { boundary: "operator-enforced"; allowNavigation(url: URL): Promise<boolean> | boolean };
  verifiedLightpandaMethods?: readonly LightpandaVerifiedMethod[];
}

export interface ManagedBrowserSession {
  describe(): AutomationSessionDescription;
  backend: BrowserControlBackend;
  /** Use this transport so metadata calls also receive lifetime/owner admission. */
  transport: BrowserControlTransport;
  close(): Promise<void>;
}

/** One owned context or a fresh-page subset of an explicitly shared context. */
export async function allocateManagedBrowserSession(input: ManagedBrowserSessionOptions): Promise<ManagedBrowserSession> {
  const owner = input.owner;
  const { isolation, ttlMs } = automationSessionOptionsSchema.parse(input.options);
  const maxTabs = input.maxTabs ?? 4;
  if (!["playwright", "lightpanda"].includes(input.backend) || !owner || owner.length > 256 || !Number.isInteger(ttlMs) || ttlMs < 1000 || ttlMs > 3_600_000 ||
      !Number.isInteger(maxTabs) || maxTabs < 1 || maxTabs > 16) {
    throw new BrowserControlError("INVALID_ARGUMENTS", "Invalid managed session resource or ownership policy.");
  }
  const shared = (): BrowserContext => {
    if (!input.sharedContext) throw new BrowserControlError("ISOLATION_UNAVAILABLE", "Shared storage requires an operator-selected context.");
    return input.sharedContext;
  };
  await input.authorize(owner);
  const ownsContext = isolation === "isolated";
  const sessionId = crypto.randomUUID();
  const expiresAt = Date.now() + ttlMs;
  const pages = new Map<string, Page>();
  const popups = new Set<Page>();
  let closed = false;
  let closing: Promise<void> | undefined;
  let creating = 0;

  const active = (): void => {
    if (closed || Date.now() >= expiresAt) throw new BrowserControlError("SESSION_CLOSED", "The automation session is closed or expired.");
  };
  const admit = async (): Promise<void> => {
    active();
    await input.authorize(owner);
    active();
  };
  const navigationAllowed = async (value: string): Promise<void> => {
    let url: URL;
    try { url = new URL(value); } catch { throw new BrowserControlError("INVALID_ARGUMENTS", "Use an absolute navigation URL."); }
    if (url.username || url.password || !["http:", "https:"].includes(url.protocol) ||
        !await input.network.allowNavigation(url)) {
      throw new BrowserControlError("ACCESS_DENIED", "The session navigation policy refused this URL.");
    }
    active();
  };
  const getPage = async (id: string): Promise<Page> => {
    await admit();
    const page = pages.get(id);
    if (!page || page.isClosed()) throw new BrowserControlError("TAB_NOT_FOUND", "The tab is not owned by this session.");
    return page;
  };
  const info = (id: string, page: Page): BrowserTabInfo => ({ id, url: page.url() });
  const newTab = async (url?: string): Promise<BrowserTabInfo> => {
    await admit();
    if (url !== undefined) await navigationAllowed(url);
    if (pages.size + creating >= maxTabs) throw new BrowserControlError("RESOURCE_LIMIT", "The session tab limit has been reached.");
    creating++;
    let page: Page | undefined;
    try {
      page = await context.newPage();
      await admit();
      const id = crypto.randomUUID();
      pages.set(id, page);
      page.once("close", () => pages.delete(id));
      // Popups are not implicitly session-owned. Do not expose or retain them.
      page.on("popup", (popup) => {
        popups.add(popup);
        void popup.close().then(() => popups.delete(popup)).catch(() => undefined);
      });
      if (url !== undefined) await page.goto(url, { waitUntil: "domcontentloaded", timeout: 10_000 });
      await admit();
      return info(id, page);
    } catch (error) {
      if (page) await page.close().catch(() => undefined);
      throw error;
    } finally { creating--; }
  };
  const binding: PlaywrightBrowserBinding = {
    async listTabs() { await admit(); return [...pages].filter(([, page]) => !page.isClosed()).map(([id, page]) => info(id, page)); },
    getPage, newTab,
    async closeTab(id) { const page = await getPage(id); await page.close(); pages.delete(id); },
  };
  // Validate the capability profile before allocating any browser resources.
  const underlying = input.backend === "lightpanda"
    ? createLightpandaBrowserBackend(binding, input.verifiedLightpandaMethods)
    : createPlaywrightBrowserBackend(binding);
  const backend: BrowserControlBackend = {
    capabilities: underlying.capabilities,
    async execute(request: BrowserControlRequest) {
      await admit();
      if (request.method === "tab.goto") await navigationAllowed(request.params.url);
      const value = await underlying.execute(request);
      try { await admit(); }
      catch {
        throw new BrowserControlError("SESSION_CLOSED", "Session access ended while the command was running.", browserControlMutates(request.method));
      }
      return value;
    },
  };
  const context = ownsContext
    ? await input.browser.newContext({ serviceWorkers: "block", acceptDownloads: false })
    : shared();
  const close = (): Promise<void> => {
    closed = true;
    clearTimeout(timer);
    if (closing) return closing;
    // The borrowed browser and shared context remain alive; close only owned resources.
    closing = (async () => {
      if (ownsContext) await context.close();
      else {
        const results = await Promise.allSettled([...pages.values(), ...popups].map((page) => page.close()));
        if (results.some((result) => result.status === "rejected")) throw new BrowserControlError("CLEANUP_FAILED", "Some session pages could not be closed.");
      }
      pages.clear();
      popups.clear();
    })().catch(() => {
      closing = undefined; // A later explicit close can retry resource cleanup.
      throw new BrowserControlError("CLEANUP_FAILED", "Session resources could not be fully closed.");
    });
    return closing;
  };
  const timer = setTimeout(() => { void close().catch(() => undefined); }, ttlMs);
  // Node can release an idle session timer; browser runtimes return a number.
  const timerHandle = timer as unknown as { unref?: () => void };
  timerHandle.unref?.();
  try { await newTab(); }
  catch (error) { await close().catch(() => undefined); throw error; }
  return {
    backend, close, transport: createBrowserControlProxy(backend, { authorize: admit }),
    describe() {
      active();
      return {
        version: 1, sessionId, backend: input.backend, isolation: isolation,
        ownedTabIds: [...pages.keys()], expiresAt: new Date(expiresAt).toISOString(),
      };
    },
  };
}
