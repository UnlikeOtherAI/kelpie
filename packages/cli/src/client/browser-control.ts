import { createNativeBrowserTransport, browserControlMutates } from "@unlikeotherai/kelpie-shared/browser-control";
import type { BrowserControlTransport } from "@unlikeotherai/kelpie-shared/browser-control";
import type { DiscoveredDevice } from "../types.js";
import { sendCommand } from "./http-client.js";
export function nativeBrowserTransport(device: DiscoveredDevice, timeout = 30_000): BrowserControlTransport {
  return createNativeBrowserTransport(async (request) => {
    const result = await sendCommand(device, "browserControl", request, timeout, { autoPair: false });
    if (result.ok || (result.data && typeof result.data === "object" && "version" in result.data && result.data.version === 1 && "ok" in result.data)) return result.data;
    return { version: 1, ok: false, error: {
      code: result.status === 401 || result.status === 403 ? "ACCESS_DENIED" : result.status === 404 ? "UNSUPPORTED" : "COMMAND_FAILED",
      message: "Native browser gateway unavailable or request failed. Pair explicitly if required.",
      mayHaveCompleted: (browserControlMutates(request.method) || request.tabId !== undefined) && ![400, 401, 403, 404].includes(result.status),
    } };
  });
}
