import type { Frame, JSHandle, Page } from "playwright-core";
import { BrowserControlError } from "./protocol.js";

type Direction = "back" | "forward";
const failed = (code: string, message: string) => new BrowserControlError(code, message, true);

/**
 * Dispatch history once. Only an observed main-frame transition gets a bounded
 * interactive-readiness check; the original document handle fences replacements.
 * A zero timeout preserves Playwright's existing no-deadline semantics.
 */
export async function navigateHistory(
  page: Page, direction: Direction, timeout: number, now: () => number = () => performance.now(),
): Promise<void> {
  const started = now();
  let transitions = 0;
  const onNavigated = (frame: Frame): void => { if (frame === page.mainFrame()) transitions++; };
  const remaining = (): number => {
    if (timeout === 0) return 0;
    const value = Math.floor(timeout - (now() - started));
    if (value <= 0) throw failed("TIMEOUT", "History navigation exceeded its deadline.");
    return value;
  };
  const within = async <T>(operation: () => Promise<T>): Promise<T> => {
    const ms = remaining();
    if (timeout === 0) return operation();
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      return await Promise.race([
        operation(),
        new Promise<never>((_, reject) => { timer = setTimeout(() => { reject(failed("TIMEOUT", "History navigation exceeded its deadline.")); }, ms); }),
      ]);
    } finally { if (timer) clearTimeout(timer); }
  };
  const unchanged = (): void => {
    if (transitions !== 1) throw failed("HISTORY_DOCUMENT_CHANGED", "The history document changed before it became ready.");
  };
  let documentHandle: JSHandle<Document> | undefined;
  let readyHandle: JSHandle<unknown> | undefined;
  page.on("framenavigated", onNavigated);
  try {
    const response = await within(() => direction === "back"
      ? page.goBack({ waitUntil: "commit", timeout: remaining() })
      : page.goForward({ waitUntil: "commit", timeout: remaining() }));
    // Playwright returns null for both no history and same-document navigation.
    // Only the main-frame navigation event distinguishes those cases.
    if (transitions === 0) {
      remaining();
      if (response !== null) throw failed("HISTORY_OBSERVATION_MISSING", "The history commit could not be observed.");
      return;
    }
    unchanged();
    let acquiring: Promise<JSHandle<Document>> | undefined;
    try { documentHandle = await within(() => (acquiring = page.evaluateHandle(() => document))); }
    catch (error) { if (acquiring) void acquiring.then(handle => handle.dispose()).catch(() => undefined); throw error; }
    unchanged();
    const waiting = page.waitForFunction(
      (expected: Document) => document === expected && document.readyState !== "loading",
      documentHandle, { timeout: remaining() },
    );
    try { readyHandle = await within(() => waiting); }
    catch (error) { void waiting.then(handle => handle.dispose()).catch(() => undefined); throw error; }
    unchanged();
    const observedDocument = documentHandle;
    const same = await within(() => observedDocument.evaluate(expected => expected === document));
    if (!same) throw failed("HISTORY_DOCUMENT_CHANGED", "The history document changed before it became ready.");
    unchanged();
    remaining();
  } finally {
    page.off("framenavigated", onNavigated);
    // Disposals are idempotent and must not extend the public deadline.
    if (readyHandle) void readyHandle.dispose().catch(() => undefined);
    if (documentHandle) void documentHandle.dispose().catch(() => undefined);
  }
}
