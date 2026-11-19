import { BROWSER_CONTROL_DOCUMENTATION } from "@unlikeotherai/kelpie-shared/browser-control";
import type { BrowserControlRequest, BrowserControlResponse } from "@unlikeotherai/kelpie-shared/browser-control";

/** The CLI exposes protocol help before it has a native target. */
export function browserControlHelp(request: BrowserControlRequest): BrowserControlResponse | undefined {
  if (request.method === "documentation") return { version: 1, ok: true, value: BROWSER_CONTROL_DOCUMENTATION };
  if (request.method === "capabilities") {
    return { version: 1, ok: true, value: { version: 1, methods: ["documentation", "capabilities"], extensions: [] } };
  }
  return undefined;
}
