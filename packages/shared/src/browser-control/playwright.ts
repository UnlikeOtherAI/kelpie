import type { Page, Locator, FrameLocator, ElementHandle } from "playwright-core";
import { BrowserControlError, browserControlMutates } from "./protocol.js";
import type { BrowserControlBackend, BrowserControlRequest, BrowserLocator, BrowserTextMatcher, BrowserTabInfo } from "./protocol.js";
import { browserControlCapabilities } from "./proxy.js";
import { collectBrowserSnapshot } from "./snapshot.js";

const matcher = (value: BrowserTextMatcher): string | RegExp => typeof value === "string" ? value : new RegExp(value.source, value.flags);
const selector = (value: BrowserTextMatcher): string => {
  if (typeof value !== "string") throw new BrowserControlError("INVALID_ARGUMENTS", "CSS and frame selectors must be strings.");
  return value;
};
export function resolvePlaywrightLocator(page: Page, query: BrowserLocator): Locator {
  let scope: Page | Locator | FrameLocator = page;
  for (const step of query) {
    switch (step.kind) {
      case "role": scope = scope.getByRole(step.role as Parameters<Page["getByRole"]>[0], { name: step.name === undefined ? undefined : matcher(step.name), exact: step.exact }); break;
      case "label": scope = scope.getByLabel(matcher(step.value), { exact: step.exact }); break;
      case "text": scope = scope.getByText(matcher(step.value), { exact: step.exact }); break;
      case "placeholder": scope = scope.getByPlaceholder(matcher(step.value), { exact: step.exact }); break;
      case "testId": scope = scope.getByTestId(matcher(step.value)); break;
      case "css": scope = scope.locator(selector(step.value)); break;
      case "frame": scope = scope.frameLocator(selector(step.value)); break;
      case "nth": {
        if (!("nth" in scope)) throw new BrowserControlError("INVALID_ARGUMENTS", "nth requires an element locator.");
        const elementScope = scope as Locator;
        scope = step.index === -1 ? elementScope.last() : elementScope.nth(step.index); break;
      }
      case "filter": {
        if (!("filter" in scope)) throw new BrowserControlError("INVALID_ARGUMENTS", "filter requires an element locator.");
        scope = (scope as Locator).filter({ hasText: step.hasText === undefined ? undefined : matcher(step.hasText), visible: step.visible }); break;
      }
    }
  }
  if (!("elementHandle" in scope)) throw new BrowserControlError("INVALID_ARGUMENTS", "Choose an element inside the frame.");
  return scope;
}

export interface PlaywrightBrowserBinding {
  /** Only the pages this session may reach, never every page of a shared context. */
  listTabs(): Promise<BrowserTabInfo[]>;
  getPage(tabId: string): Promise<Page>;
  newTab?(url?: string): Promise<BrowserTabInfo>;
  closeTab?(tabId: string): Promise<void>;
  selectTab?(tabId: string): Promise<void>;
}

/** Browserbase, local Chromium and test browsers use the same page implementation. Allocation stays outside it. */
export function createPlaywrightBrowserBackend(binding: PlaywrightBrowserBinding): BrowserControlBackend {
  const capabilities = browserControlCapabilities();
  const references = new Map<string, Map<string, ElementHandle>>();
  let generation = 0;
  const clear = async (id: string): Promise<void> => {
    const old = references.get(id);
    references.delete(id);
    await Promise.allSettled(Array.from(old?.values() ?? []).map((handle) => handle.dispose()));
  };
  if (!binding.selectTab) capabilities.methods = capabilities.methods.filter((method) => method !== "tabs.select");
  if (!binding.newTab) capabilities.methods = capabilities.methods.filter((method) => method !== "tabs.new");
  if (!binding.closeTab) capabilities.methods = capabilities.methods.filter((method) => method !== "tabs.close");
  return {
    capabilities,
    async execute(request) {
      if (request.method === "tabs.list") return binding.listTabs();
      if (request.method === "tabs.new" && binding.newTab) return binding.newTab(request.params.url);
      // The resolver must revalidate the session's ownership for every call.
      if (!request.tabId) throw new BrowserControlError("TAB_REQUIRED", "Choose a browser tab.");
      if (request.method === "tabs.select" && binding.selectTab) return binding.selectTab(request.tabId);
      if (request.method === "tabs.close" && binding.closeTab) {
        await clear(request.tabId);
        return binding.closeTab(request.tabId);
      }
      const page = await binding.getPage(request.tabId);
      if (request.method === "tab.snapshot") {
        await clear(request.tabId);
        const collected = await page.evaluateHandle(collectBrowserSnapshot, { ...request.params, prefix: `s${String(++generation)}e` });
        try {
          const snap = await collected.getProperty("snapshot");
          const value: unknown = await snap.jsonValue();
          await snap.dispose();
          const targets = await collected.getProperty("targets");
          const properties = await targets.getProperties();
          const refs = new Map<string, ElementHandle>();
          for (const [ref, handle] of properties) {
            const element = handle.asElement() as ElementHandle<Element> | null;
            if (element) refs.set(ref, element);
            else await handle.dispose();
          }
          references.set(request.tabId, refs);
          await targets.dispose();
          return value;
        } finally { await collected.dispose(); }
      }
      if (request.method === "tab.click" || request.method === "tab.type") {
        const handle = references.get(request.tabId)?.get(request.params.ref);
        if (!handle || !await handle.evaluate((el) => el.isConnected)) throw new BrowserControlError("STALE_REFERENCE", "Observe this tab again before acting.");
        try {
          if (request.method === "tab.click") await handle.click({ timeout: 10_000 });
          else {
            const editable = await handle.evaluate((el) => el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement || (el instanceof HTMLElement && el.isContentEditable));
            if (!editable) throw new BrowserControlError("INVALID_TARGET", "Choose an editable element from a new snapshot.");
            await handle.fill(await handle.evaluate((el) => el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement ? el.value : el.textContent ?? "") + request.params.text, { timeout: 10_000 });
          }
          return null;
        } finally { await clear(request.tabId); }
      }
      try { return await executePlaywrightPage(page, request); }
      finally { if (browserControlMutates(request.method)) await clear(request.tabId); }
    },
  };
}

export async function executePlaywrightPage(page: Page, request: BrowserControlRequest): Promise<unknown> {
  const params = request.params;
  const timeout = "timeoutMs" in params ? params.timeoutMs ?? 10_000 : 10_000;
  if ("locator" in params) {
    const target = resolvePlaywrightLocator(page, params.locator);
    switch (request.method) {
      case "locator.click": await target.click({ timeout, button: request.params.button, modifiers: request.params.modifiers }); return null;
      case "locator.dblclick": await target.dblclick({ timeout }); return null;
      case "locator.fill": await target.fill(request.params.value, { timeout }); return null;
      case "locator.type": await target.pressSequentially(request.params.text, { timeout }); return null;
      case "locator.press": await target.press(request.params.key, { timeout }); return null;
      case "locator.check": await target.check({ timeout }); return null;
      case "locator.uncheck": await target.uncheck({ timeout }); return null;
      case "locator.selectOption": {
        const value = request.params.value;
        return target.selectOption(Array.isArray(value) ? value.map((option) => typeof option === "string" ? { value: option } : option) : value, { timeout });
      }
      case "locator.innerText": return target.innerText({ timeout });
      case "locator.textContent": return target.textContent({ timeout });
      case "locator.getAttribute": return target.getAttribute(request.params.name, { timeout });
      case "locator.count": return target.count();
      case "locator.isVisible": return target.isVisible();
      case "locator.isEnabled": return target.isEnabled({ timeout });
      case "locator.waitFor": await target.waitFor({ timeout, state: request.params.state ?? "visible" }); return null;
    }
  }
  switch (request.method) {
    case "tab.goto": await page.goto(request.params.url, { waitUntil: "domcontentloaded", timeout }); return null;
    case "tab.back": await page.goBack({ waitUntil: "domcontentloaded", timeout }); return null;
    case "tab.forward": await page.goForward({ waitUntil: "domcontentloaded", timeout }); return null;
    case "tab.reload": await page.reload({ waitUntil: "domcontentloaded", timeout }); return null;
    case "tab.url": return page.url();
    case "tab.title": return page.title();
    case "tab.snapshot": return (await page.evaluate(collectBrowserSnapshot, { ...request.params, prefix: "e" })).snapshot;
    case "tab.screenshot": {
      const type = request.params.format ?? "png";
      const bytes = await page.screenshot({ type, fullPage: request.params.fullPage, ...(type === "jpeg" ? { quality: request.params.quality } : {}) });
      return { type: "image", mimeType: `image/${type}`, data: bytes.toString("base64") };
    }
    case "page.press": await page.keyboard.press(request.params.key); return null;
    case "page.scroll": await page.mouse.wheel(request.params.deltaX, request.params.deltaY); return null;
    default: throw new BrowserControlError("UNSUPPORTED", `This page does not implement ${request.method}.`);
  }
}
