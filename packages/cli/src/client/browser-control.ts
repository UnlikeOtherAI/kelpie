import { createNativeBrowserTransport, browserControlMutates } from "@unlikeotherai/kelpie-shared/browser-control";
import type { DiscoveredDevice } from "../types.js";
import { sendCommand } from "./http-client.js";
export function nativeBrowserTransport(device: DiscoveredDevice, timeout = 30_000) {
  return createNativeBrowserTransport<{ device?: DiscoveredDevice; pairingTargetHint?: string }>(async (request, context) => {
    const result = await sendCommand(context?.device ?? device, "browserControl", request, timeout, {
      pairingTargetHint: request.tabId ? context?.pairingTargetHint : undefined,
    });
    if (result.ok || (result.data && typeof result.data === "object" && "version" in result.data && result.data.version === 1 && "ok" in result.data)) return result.data;
    const error = (result.data as { error?: { code?: string; message?: string } } | null)?.error;
    const clientError = result.status === 0 || result.status === 408 || error?.code === "PAIR_TARGET_REQUIRED";
    return { version: 1, ok: false, error: {
      code: clientError && error?.code ? error.code
        : result.status === 401 || result.status === 403 ? "ACCESS_DENIED" : result.status === 404 ? "UNSUPPORTED" : "COMMAND_FAILED",
      message: clientError && error?.message ? error.message
        : "Native browser gateway unavailable or request failed. Check the device connection and computer approval.",
      mayHaveCompleted: (browserControlMutates(request.method) || request.tabId !== undefined) && ![400, 401, 403, 404].includes(result.status),
    } };
  });
}
