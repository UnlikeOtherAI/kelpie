import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import {
  BROWSER_CONTROL_DESCRIPTION, BrowserControlRequestSchema, BrowserControlError,
  createBrowserControlProxy, createKelpieBrowserBackend,
} from "@unlikeotherai/kelpie-shared/browser-control";
import type { BrowserControlTransport } from "@unlikeotherai/kelpie-shared/browser-control";
import type { BrowserMcpTool } from "@unlikeotherai/kelpie-shared";
import { BrowserToolUnsupportedPlatforms } from "@unlikeotherai/kelpie-shared";
import { sendCommand } from "../client/http-client.js";
import { getDevice } from "../discovery/registry.js";
import type { DiscoveredDevice } from "../types.js";
import { browserTools } from "./tools.js";

/** One proxy per exact device socket: references cannot leak between machines or restarted listeners. */
export function registerBrowserControl(server: McpServer, pinned?: DiscoveredDevice, callableTools?: ReadonlySet<BrowserMcpTool>): void {
  const proxies = new Map<string, BrowserControlTransport>();
  server.registerTool("kelpie_browser_control", {
    description: BROWSER_CONTROL_DESCRIPTION,
    inputSchema: { device: z.string().optional(), request: BrowserControlRequestSchema },
  }, async ({ device: query, request }) => {
    const device = query ? await getDevice(query) : pinned ?? await getDevice("");
    if (!device) return { isError: true, content: [{ type: "text", text: "No browser device selected." }] };
    const key = `${device.id}@${device.ip}:${String(device.port)}`;
    let proxy = proxies.get(key);
    if (!proxy) {
      const methods = new Set(browserTools.filter((tool) => {
        if (pinned?.id === device.id && callableTools) return callableTools.has(tool.name as BrowserMcpTool);
        const denied = BrowserToolUnsupportedPlatforms[tool.name as keyof typeof BrowserToolUnsupportedPlatforms] as readonly string[] | undefined;
        return !denied?.includes(device.platform);
      }).map((tool) => tool.method));
      proxy = createBrowserControlProxy(createKelpieBrowserBackend({ methods, async call(method, params) {
        const result = await sendCommand(device, method, params, 30_000, { autoPair: false });
        if (!result.ok) {
          if (result.status === 401 || result.status === 403) throw new BrowserControlError("ACCESS_DENIED", "Pair this device before controlling its browser.");
          throw new Error("Native browser request failed.");
        }
        return result.data;
      } }));
      proxies.set(key, proxy);
    }
    const result = await proxy.call(request);
    if (result.ok && request.method === "tab.screenshot") {
      const shot = result.value as { type: "image"; data: string; mimeType: string };
      return { content: [{ type: "text", text: JSON.stringify({ ...result, value: { ...shot, data: undefined } }) }, shot] };
    }
    return { isError: !result.ok, content: [{ type: "text", text: JSON.stringify(result) }] };
  });
}
