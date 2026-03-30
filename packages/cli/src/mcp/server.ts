import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { sendCommand } from "../client/http-client.js";
import { getDevice, getAllDevices, addDevices } from "../discovery/registry.js";
import { scanForDevices } from "../discovery/scanner.js";
import { filterDevices } from "../group/filter.js";
import { executeGroup, executeSmartQuery } from "../group/orchestrator.js";
import { browserTools, cliTools } from "./tools.js";
import type { BrowserToolDef, CliToolDef } from "./tools.js";
import type { DiscoveredDevice } from "../types.js";

export function createMcpServer(): McpServer {
  const server = new McpServer(
    { name: "mollotov", version: "0.1.0" },
    { capabilities: { tools: {} } },
  );

  for (const tool of browserTools) {
    registerBrowserTool(server, tool);
  }
  for (const tool of cliTools) {
    registerCliTool(server, tool);
  }

  return server;
}

function registerBrowserTool(server: McpServer, tool: BrowserToolDef): void {
  server.registerTool(tool.name, { description: tool.description, inputSchema: tool.schema }, async (args) => {
    const deviceId = args.device as string;
    const device = getDevice(deviceId);
    if (!device) {
      return { content: [{ type: "text", text: JSON.stringify({ success: false, error: { code: "DEVICE_NOT_FOUND", message: `No device matching "${deviceId}"` } }) }] };
    }
    const body = tool.bodyFromArgs(args as Record<string, unknown>);
    const result = await sendCommand(device, tool.method, body);
    return { content: [{ type: "text", text: JSON.stringify(result.data) }] };
  });
}

function registerCliTool(server: McpServer, tool: CliToolDef): void {
  server.registerTool(tool.name, { description: tool.description, inputSchema: tool.schema }, async (args) => {
    const params = args as Record<string, unknown>;

    if (tool.kind === "discovery") {
      return handleDiscovery(tool.method, params);
    }

    const devices = getFilteredDevices(params);
    if (devices.length === 0) {
      return { content: [{ type: "text", text: JSON.stringify({ success: false, error: { code: "NO_DEVICES", message: "No devices match the filter criteria" } }) }] };
    }

    const body = tool.bodyFromArgs(params);
    const timeout = 10000;

    if (tool.kind === "smartQuery") {
      const result = await executeSmartQuery(devices, tool.method, body, timeout);
      return { content: [{ type: "text", text: JSON.stringify(result) }] };
    }

    const result = await executeGroup(devices, tool.method, body, timeout);
    return { content: [{ type: "text", text: JSON.stringify(result) }] };
  });
}

async function handleDiscovery(method: string, params: Record<string, unknown>): Promise<{ content: Array<{ type: "text"; text: string }> }> {
  if (method === "discover") {
    const timeout = (params.timeout as number) ?? 3000;
    const found = await scanForDevices(timeout);
    addDevices(found);
    const devices = getAllDevices();
    return { content: [{ type: "text", text: JSON.stringify({ success: true, devices, count: devices.length }) }] };
  }
  // listDevices
  const devices = getAllDevices();
  return { content: [{ type: "text", text: JSON.stringify({ success: true, devices, count: devices.length }) }] };
}

function getFilteredDevices(params: Record<string, unknown>): DiscoveredDevice[] {
  return filterDevices(getAllDevices(), {
    platform: params.platform as "ios" | "android" | undefined,
    include: params.include as string | undefined,
    exclude: params.exclude as string | undefined,
  });
}
