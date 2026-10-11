import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { BROWSER_CONTROL_DESCRIPTION, browserControlRequestSchema, BROWSER_CONTROL_METHODS } from "@unlikeotherai/kelpie-shared/browser-control";
import type { BrowserControlRequest, BrowserControlTransport } from "@unlikeotherai/kelpie-shared/browser-control";
import { nativeBrowserTransport } from "../client/browser-control.js";
import { getDevice } from "../discovery/registry.js";
import type { DiscoveredDevice } from "../types.js";
const nativeMethods = BROWSER_CONTROL_METHODS.filter((method) => !method.startsWith("locator."));
/** Wire forwarding only: native listener owns reference identity and capability checks. */
export function registerBrowserControl(server: McpServer, pinned?: DiscoveredDevice): { name: string; description: string; inputSchema: Record<string, unknown> } {
  const proxies = new Map<string, BrowserControlTransport>();
  const schema = { device: z.string().optional(), request: browserControlRequestSchema({ methods: nativeMethods, compact: true }) };
  server.registerTool("kelpie_browser_control", {
    description: BROWSER_CONTROL_DESCRIPTION,
    inputSchema: schema,
  }, async ({ device: query, request }) => {
    const device = query ? await getDevice(query) : pinned ?? await getDevice("");
    if (!device) return { isError: true, content: [{ type: "text", text: "No browser device selected." }] };
    const key = `${device.id}@${device.ip}:${String(device.port)}@${device.localLaunchId ?? "remote"}`;
    let proxy = proxies.get(key);
    if (!proxy) { proxy = nativeBrowserTransport(device); proxies.set(key, proxy); }
    const result = await proxy.call(request as BrowserControlRequest);
    if (result.ok && result.value && typeof result.value === "object" && "type" in result.value && result.value.type === "image") {
      const shot = result.value as { type: "image"; data: string; mimeType: string };
      return { content: [{ type: "text", text: JSON.stringify({ ...result, value: { ...shot, data: undefined } }) }, shot] };
    }
    return { isError: !result.ok, content: [{ type: "text", text: JSON.stringify(result) }] };
  });
  return { name: "kelpie_browser_control", description: BROWSER_CONTROL_DESCRIPTION, inputSchema: z.toJSONSchema(z.object(schema).strict()) };
}
