import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { deviceSelector } from "@unlikeotherai/kelpie-shared";
import { BROWSER_CONTROL_DESCRIPTION, browserControlRequestSchema, BROWSER_CONTROL_METHODS, BrowserControlRequestSchema } from "@unlikeotherai/kelpie-shared/browser-control";
import { browserControlHelp } from "../client/browser-control-help.js";
import { nativeBrowserTransport } from "../client/browser-control.js";
import { getDevice } from "../discovery/registry.js";
import type { DiscoveredDevice } from "../types.js";
const nativeMethods = BROWSER_CONTROL_METHODS.filter((method) => !method.startsWith("locator."));
const description = `${BROWSER_CONTROL_DESCRIPTION} Without a target, documentation and capabilities describe this CLI's local help. To obtain a browser's capabilities, pass device or start MCP with a pinned browser. Use kelpie_discover to find targets.`;
export const mcpDeviceHint = "Pass device (ID, name, IP address, or host:port). Use kelpie_list_devices for cached devices or kelpie_discover to scan.";
export const mcpTabPairingHint = `The discovered browser requires pairing. Select the browser that owns the tab. ${mcpDeviceHint}`;

/** Wire forwarding only: native listener owns reference identity and capability checks. */
export function registerBrowserControl(server: McpServer, pinned?: DiscoveredDevice): { name: string; description: string; inputSchema: Record<string, unknown> } {
  const proxies = new Map<string, ReturnType<typeof nativeBrowserTransport>>();
  const schema = { device: deviceSelector.optional(), request: browserControlRequestSchema({ methods: nativeMethods, compact: true }) };
  server.registerTool("kelpie_browser_control", {
    description,
    inputSchema: schema,
  }, async ({ device: query, request }) => {
    const parsed = BrowserControlRequestSchema.safeParse(request);
    if (!parsed.success) {
      const error = { code: "INVALID_ARGUMENTS", message: "The browser request does not match the version 1 contract.", mayHaveCompleted: false };
      return { isError: true, content: [{ type: "text", text: JSON.stringify({ version: 1, ok: false, error }) }] };
    }
    const explicitTarget = Boolean(query) || pinned !== undefined;
    const help = explicitTarget ? undefined : browserControlHelp(parsed.data);
    if (help) return { content: [{ type: "text", text: JSON.stringify(help) }] };
    const device = query ? await getDevice(query) : pinned ?? await getDevice("");
    if (!device) {
      const reason = query ? `No browser device matching "${query}".` : "No browser device selected.";
      return { isError: true, content: [{ type: "text", text: `${reason} ${mcpDeviceHint}` }] };
    }
    const key = JSON.stringify([device.id, device.ip, device.port, device.localLaunchId]);
    let proxy = proxies.get(key);
    if (!proxy) {
      proxy = nativeBrowserTransport(device);
      proxies.set(key, proxy);
    }
    const result = await proxy.call(parsed.data, {
      device,
      pairingTargetHint: explicitTarget ? undefined : mcpTabPairingHint,
    });
    if (result.ok && result.value && typeof result.value === "object" && "type" in result.value && result.value.type === "image") {
      const shot = result.value as { type: "image"; data: string; mimeType: string };
      return { content: [{ type: "text", text: JSON.stringify({ ...result, value: { ...shot, data: undefined } }) }, shot] };
    }
    return { isError: !result.ok, content: [{ type: "text", text: JSON.stringify(result) }] };
  });
  return { name: "kelpie_browser_control", description, inputSchema: z.toJSONSchema(z.object(schema).strict()) };
}
