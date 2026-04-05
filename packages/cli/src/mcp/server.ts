import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { sendCommand } from "../client/http-client.js";
import { getDevice, getAllDevices, addDevices } from "../discovery/registry.js";
import { scanForDevices } from "../discovery/scanner.js";
import { filterDevices } from "../group/filter.js";
import { executeGroup, executeSmartQuery } from "../group/orchestrator.js";
import { browserTools, cliTools } from "./tools.js";
import type { BrowserToolDef, CliToolDef } from "./tools.js";
import type { DiscoveredDevice } from "../types.js";
import type { Platform } from "@unlikeotherai/kelpie-shared";
import { join } from "node:path";
import { getApprovedModels, findModel } from "../ai/models.js";
import { ModelStore } from "../ai/store.js";
import { buildDownloadUrl, downloadModel } from "../ai/download.js";
import { detectOllama, listOllamaModels } from "../ai/ollama.js";

export function createMcpServer(): McpServer {
  const server = new McpServer(
    { name: "kelpie", version: "0.1.0" },
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
    const device = await getDevice(deviceId);
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

async function handleDiscovery(method: string, params: Record<string, unknown>): Promise<{ content: { type: "text"; text: string }[] }> {
  if (method === "aiModels") {
    const store = new ModelStore();
    const approved = getApprovedModels();
    const downloaded = store.listDownloaded();
    const rows = approved.map((m) => ({
      id: m.id,
      name: m.name,
      quantization: m.quantization,
      sizeGB: +(m.sizeBytes / 1_073_741_824).toFixed(1),
      downloaded: downloaded.some((d) => d.id === m.id),
    }));
    const result: Record<string, unknown> = { success: true, models: rows };
    const ollama = await detectOllama();
    if (ollama) {
      const ollamaModels = await listOllamaModels();
      result.ollama = { endpoint: "http://localhost:11434", models: ollamaModels };
    }
    return { content: [{ type: "text" as const, text: JSON.stringify(result) }] };
  }

  if (method === "aiPull") {
    const modelId = params.model as string;
    const model = findModel(modelId);
    if (!model) {
      return { content: [{ type: "text" as const, text: JSON.stringify({ success: false, error: { code: "MODEL_NOT_FOUND", message: `Unknown model "${modelId}"` } }) }] };
    }
    const store = new ModelStore();
    if (store.isDownloaded(modelId)) {
      return { content: [{ type: "text" as const, text: JSON.stringify({ success: true, message: "Already downloaded", path: store.getModelPath(modelId) }) }] };
    }
    try {
      const url = buildDownloadUrl(model.huggingFaceRepo, model.huggingFaceFile);
      const destPath = join(store.getModelDir(modelId), "model.gguf");
      await downloadModel(url, destPath, model.sha256);
      store.register(modelId, { name: model.name, capabilities: [...model.capabilities] });
      return { content: [{ type: "text" as const, text: JSON.stringify({ success: true, model: modelId, path: destPath }) }] };
    } catch (err) {
      return { content: [{ type: "text" as const, text: JSON.stringify({ success: false, error: { code: "DOWNLOAD_FAILED", message: (err as Error).message } }) }] };
    }
  }

  if (method === "aiRemove") {
    const modelId = params.model as string;
    const store = new ModelStore();
    if (!store.isDownloaded(modelId)) {
      return { content: [{ type: "text" as const, text: JSON.stringify({ success: false, error: { code: "MODEL_NOT_FOUND", message: `Model "${modelId}" is not downloaded` } }) }] };
    }
    store.remove(modelId);
    return { content: [{ type: "text" as const, text: JSON.stringify({ success: true, message: `Model ${modelId} removed` }) }] };
  }

  if (method === "discover") {
    const timeout = typeof params.timeout === "number" ? params.timeout : 3000;
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
    platform: params.platform as Platform | undefined,
    include: params.include as string | undefined,
    exclude: params.exclude as string | undefined,
  });
}
