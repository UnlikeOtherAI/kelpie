import { BrowserControlError } from "./protocol.js";
import type { BrowserControlBackend, BrowserControlMethod } from "./protocol.js";
import type { PlaywrightBrowserBinding } from "./playwright.js";
import { executePlaywrightPage } from "./playwright.js";

/** Candidates, not an assertion of upstream CDP conformance. No layout/pixel APIs. */
export const LIGHTPANDA_CANDIDATE_METHODS = [
  "tabs.list", "tabs.new", "tabs.close", "tab.goto", "tab.back", "tab.forward",
  "tab.reload", "tab.url", "tab.title",
  "tab.snapshot", "tab.extract", "tab.status", "tab.ready",
] as const satisfies readonly BrowserControlMethod[];
export type LightpandaVerifiedMethod = typeof LIGHTPANDA_CANDIDATE_METHODS[number];

/**
 * Allocation and version-specific conformance belong to the trusted operator.
 * No method is admitted by default. Never treat text-layout PNG as browser pixels.
 */
export function createLightpandaBrowserBackend(
  binding: PlaywrightBrowserBinding,
  verifiedMethods: readonly LightpandaVerifiedMethod[] = [],
): BrowserControlBackend {
  const candidates = new Set<string>(LIGHTPANDA_CANDIDATE_METHODS);
  const admitted = new Set<BrowserControlMethod>();
  for (const method of verifiedMethods) {
    if (!candidates.has(method)) throw new BrowserControlError("UNSUPPORTED", "The restricted worker cannot admit this method.");
    if (method === "tabs.new" && !binding.newTab || method === "tabs.close" && !binding.closeTab) {
      throw new BrowserControlError("UNSUPPORTED", "The worker binding does not implement this tab operation.");
    }
    admitted.add(method);
  }
  return {
    capabilities: { version: 1, methods: ["documentation", "capabilities", ...admitted], extensions: [] },
    async execute(request) {
      // Keep a private inventory: editing public capability metadata cannot grant access.
      if (!admitted.has(request.method)) {
        throw new BrowserControlError("UNSUPPORTED", "This restricted worker does not implement the requested method.");
      }
      if (request.method === "tabs.list") return binding.listTabs();
      if (request.method === "tabs.new" && binding.newTab) return binding.newTab(request.params.url);
      if (!request.tabId) throw new BrowserControlError("TAB_REQUIRED", "Choose a session-owned tab.");
      if (request.method === "tabs.close" && binding.closeTab) return binding.closeTab(request.tabId);
      return executePlaywrightPage(await binding.getPage(request.tabId), request);
    },
  };
}
