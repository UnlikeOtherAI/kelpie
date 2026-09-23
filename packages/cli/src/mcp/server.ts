import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";
import { randomUUID } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { pathToFileURL } from "node:url";
import { sendCommand } from "../client/http-client.js";
import { getDevice, getAllDevices, addDevices } from "../discovery/registry.js";
import { discoverDevices } from "../discovery/discover.js";
import { filterDevices } from "../group/filter.js";
import { executeGroup, executeSmartQuery } from "../group/orchestrator.js";
import { browserTools, cliTools, requestTimeoutMs } from "./tools.js";
import type { BrowserToolDef, CliToolDef } from "./tools.js";
import type { DiscoveredDevice } from "../types.js";
import { BrowserToolUnsupportedPlatforms, type BrowserMcpTool, type Platform } from "@unlikeotherai/kelpie-shared";
import { getApprovedModels, findModel } from "../ai/models.js";
import { ModelStore } from "../ai/store.js";
import { buildDownloadUrl, downloadModel } from "../ai/download.js";
import { detectOllama, listOllamaModels } from "../ai/ollama.js";
import { saveFeedbackReport, summarizeFeedbackReports } from "../feedback/store.js";
import { pair as pairWithDevice } from "../auth/pairing.js";
import { defaultClientName, getSessionCache, getTokenStore } from "../auth/token-store.js";

type JsonObject = Record<string, unknown>;
type ScreenshotResult = JsonObject & {
  image: string;
  format?: unknown;
  resolution?: unknown;
  success?: unknown;
};

const screenshotMethods = new Set(["screenshot", "screenshotAnnotated"]);
const mcpScreenshotDir = join(tmpdir(), "kelpie-mcp-screenshots");

/**
 * `pinned` is the local browser `kelpie --browser <alias> mcp` was started
 * for. It becomes the target of every tool call that omits `device`, so a
 * client driving one launched browser does not have to name it on each call
 * — and cannot silently land on whatever discovery finds first. An explicit
 * `device` argument still wins.
 *
 * `callableTools` is the runtime's own answer about what it can actually do.
 * When it is supplied, only those tools are registered, so the catalogue never
 * advertises a tool the pinned browser would reject.
 */
export function createMcpServer(pinned?: DiscoveredDevice, callableTools?: ReadonlySet<BrowserMcpTool>): McpServer {
  const server = new McpServer(
    {
      name: "kelpie",
      version: "0.1.0",
      description:
        "LLM-first browser automation server. When a tool fails unexpectedly, platform behavior is inconsistent, or a missing capability blocks the task, report it after checking for duplicates at https://github.com/UnlikeOtherAI/kelpie/issues with the command, parameters, platform, error, and expected behavior.",
    },
    { capabilities: { tools: {} } },
  );

  for (const tool of browserTools) {
    if (!isCallableOnPinnedDevice(tool, pinned, callableTools)) continue;
    registerBrowserTool(server, tool, pinned);
  }
  for (const tool of cliTools) {
    registerCliTool(server, tool, pinned);
  }

  return server;
}

/** The device a tool call targets: an explicit `device` first, else the pinned alias. */
async function resolveDevice(
  query: string | undefined,
  pinned: DiscoveredDevice | undefined,
): Promise<DiscoveredDevice | undefined> {
  if (!query) return pinned ?? (await getDevice(""));
  return getDevice(query);
}

/**
 * Whether the pinned browser can actually run this tool. `callableTools` is
 * the runtime's own inventory and wins when present; otherwise fall back to
 * the shared per-platform unsupported table. With no pinned device the
 * catalogue stays complete, because any device may answer the call.
 */
function isCallableOnPinnedDevice(
  tool: BrowserToolDef,
  pinned?: DiscoveredDevice,
  callableTools?: ReadonlySet<BrowserMcpTool>,
): boolean {
  if (!pinned) return true;
  if (callableTools) return callableTools.has(tool.name as BrowserMcpTool);
  if (!(tool.name in BrowserToolUnsupportedPlatforms)) return true;
  const unsupported = BrowserToolUnsupportedPlatforms[tool.name as keyof typeof BrowserToolUnsupportedPlatforms] as readonly Platform[];
  return !unsupported.includes(pinned.platform);
}

function registerBrowserTool(
  server: McpServer,
  tool: BrowserToolDef,
  pinned?: DiscoveredDevice,
): void {
  // With a pinned browser `device` is optional: omitting it targets the alias.
  const deviceSchema = tool.schema.device;
  const schema = pinned && deviceSchema
    ? { ...tool.schema, device: deviceSchema.optional() }
    : tool.schema;
  server.registerTool(tool.name, { description: describeTool(tool.description, tool.platforms), inputSchema: schema }, async (args) => {
    const deviceId = args.device as string | undefined;
    const device = await resolveDevice(deviceId, pinned);
    if (!device) {
      return errorToolResult({ success: false, error: { code: "DEVICE_NOT_FOUND", message: `No device matching "${deviceId}"` } });
    }
    const body = tool.bodyFromArgs(args as Record<string, unknown>);
    const result = await sendCommand(device, tool.method, body, requestTimeoutMs(tool, args as Record<string, unknown>));
    if (tool.method === "reportIssue" && result.ok && (result.data as { success?: boolean }).success === true) {
      const remote = result.data as {
        reportId?: string;
        storedAt?: string;
      };
      await saveFeedbackReport(body as unknown as Parameters<typeof saveFeedbackReport>[0], {
        deviceId: device.id,
        deviceName: device.name,
        remoteReportId: remote.reportId,
        remoteStoredAt: remote.storedAt,
      });
    }
    return formatBrowserToolResult(tool.method, result.data, device.name);
  });
}

export async function formatBrowserToolResult(
  method: string,
  data: unknown,
  deviceName?: string,
): Promise<CallToolResult> {
  if (isScreenshotResult(method, data)) {
    if (isNativeScreenshotResult(method, data)) {
      return saveNativeScreenshotResult(method, data, deviceName);
    }
    return portableScreenshotResult(data);
  }
  return textToolResult(data);
}

function textToolResult(data: unknown): CallToolResult {
  return {
    content: [{ type: "text", text: JSON.stringify(data) }],
    ...(isMcpFailure(data) ? { isError: true } : {}),
  };
}

function errorToolResult(data: unknown): { content: { type: "text"; text: string }[]; isError: true } {
  return { content: [{ type: "text", text: JSON.stringify(data) }], isError: true };
}

function isMcpFailure(data: unknown): boolean {
  return isJsonObject(data) && data.success === false;
}

function isScreenshotResult(method: string, data: unknown): data is ScreenshotResult {
  return (
    screenshotMethods.has(method) &&
    isJsonObject(data) &&
    data.success === true &&
    typeof data.image === "string" &&
    data.image.length > 0
  );
}

function isNativeScreenshotResult(method: string, data: unknown): data is ScreenshotResult {
  return (
    isScreenshotResult(method, data) &&
    data.resolution === "native" &&
    typeof data.image === "string"
  );
}

function portableScreenshotResult(result: ScreenshotResult): CallToolResult {
  const format = normalizeImageFormat(result.format);
  const mimeType = `image/${format}`;
  const metadata: JsonObject = { ...result, mimeType };
  return {
    content: [
      { type: "text", text: JSON.stringify(metadata) },
      { type: "image", data: result.image, mimeType },
    ],
    structuredContent: metadata,
  };
}

async function saveNativeScreenshotResult(
  method: string,
  result: ScreenshotResult,
  deviceName: string | undefined,
): Promise<CallToolResult> {
  const format = normalizeImageFormat(result.format);
  const extension = format === "jpeg" ? "jpg" : "png";
  const imageBytes = Buffer.from(result.image, "base64");
  const file = await writeMcpScreenshotFile(imageBytes, extension, method, deviceName);
  const { image: _image, ...metadata } = result;
  const compactResult: JsonObject = {
    ...metadata,
    file,
    imageSavedToFile: true,
    imageBytes: imageBytes.byteLength,
  };

  return {
    content: [
      { type: "text", text: JSON.stringify(compactResult) },
      { type: "image", data: result.image, mimeType: `image/${format}` },
      {
        type: "resource_link",
        uri: pathToFileURL(file).href,
        name: basename(file),
        mimeType: `image/${format}`,
        size: imageBytes.byteLength,
        description: "Native screenshot saved by Kelpie MCP",
      },
    ],
    structuredContent: compactResult,
  };
}

async function writeMcpScreenshotFile(
  imageBytes: Buffer,
  extension: "jpg" | "png",
  method: string,
  deviceName: string | undefined,
): Promise<string> {
  await mkdir(mcpScreenshotDir, { recursive: true });
  const slug = slugify(deviceName ?? method);
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const suffix = randomUUID().slice(0, 8);
  const file = join(mcpScreenshotDir, `${slug}-${timestamp}-${suffix}.${extension}`);
  await writeFile(file, imageBytes);
  return file;
}

function normalizeImageFormat(raw: unknown): "jpeg" | "png" {
  return raw === "jpeg" || raw === "jpg" ? "jpeg" : "png";
}

function slugify(value: string): string {
  const slug = value.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
  return slug.length > 0 ? slug : "screenshot";
}

function isJsonObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function registerCliTool(server: McpServer, tool: CliToolDef, pinned?: DiscoveredDevice): void {
  server.registerTool(tool.name, { description: describeTool(tool.description, tool.platforms), inputSchema: tool.schema }, async (args) => {
    const params = args as Record<string, unknown>;

    if (tool.kind === "discovery") {
      return handleDiscovery(tool.method, params, pinned);
    }

    const devices = getFilteredDevices(params);
    if (devices.length === 0) {
      return errorToolResult({ success: false, error: { code: "NO_DEVICES", message: "No devices match the filter criteria" } });
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

async function handleDiscovery(method: string, params: Record<string, unknown>, pinned?: DiscoveredDevice): Promise<{ content: { type: "text"; text: string }[] }> {
  if (method === "feedbackSummary") {
    const limit = typeof params.limit === "number" ? params.limit : 10;
    const summary = await summarizeFeedbackReports(limit);
    return { content: [{ type: "text" as const, text: JSON.stringify(summary) }] };
  }

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
      return errorToolResult({ success: false, error: { code: "MODEL_NOT_FOUND", message: `Unknown model "${modelId}"` } });
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
      return errorToolResult({ success: false, error: { code: "DOWNLOAD_FAILED", message: (err as Error).message } });
    }
  }

  if (method === "aiRemove") {
    const modelId = params.model as string;
    const store = new ModelStore();
    if (!store.isDownloaded(modelId)) {
      return errorToolResult({ success: false, error: { code: "MODEL_NOT_FOUND", message: `Model "${modelId}" is not downloaded` } });
    }
    store.remove(modelId);
    return { content: [{ type: "text" as const, text: JSON.stringify({ success: true, message: `Model ${modelId} removed` }) }] };
  }

  if (method === "discover") {
    const timeout = typeof params.timeout === "number" ? params.timeout : 3000;
    const found = await discoverDevices(timeout);
    addDevices(found);
    const devices = getAllDevices();
    return { content: [{ type: "text", text: JSON.stringify({ success: true, devices, count: devices.length }) }] };
  }
  if (method === "pair") {
    return handlePair(params, pinned);
  }
  // listDevices
  const devices = getAllDevices();
  return { content: [{ type: "text", text: JSON.stringify({ success: true, devices, count: devices.length }) }] };
}

async function handlePair(
  params: Record<string, unknown>,
  pinned?: DiscoveredDevice,
): Promise<{ content: { type: "text"; text: string }[] }> {
  const deviceId = typeof params.device === "string" ? params.device : "";
  const device = await resolveDevice(deviceId, pinned);
  if (!device) {
    return errorToolResult({ success: false, error: { code: "DEVICE_NOT_FOUND", message: `No device matching "${deviceId}"` } });
  }
  const store = getTokenStore();
  const clientId = await store.clientId();
  const clientName = typeof params.clientName === "string" ? params.clientName : defaultClientName();
  const overallTimeoutMs = typeof params.timeoutMs === "number" ? params.timeoutMs : 5 * 60_000;

  const result = await pairWithDevice({
    host: device.ip,
    port: device.port,
    clientId,
    clientName,
    overallTimeoutMs,
  });
  if (result.status !== "approved") {
    return errorToolResult({
      success: false,
      error: {
        code: result.status === "error" ? result.code : `PAIR_${result.status.toUpperCase()}`,
        message: result.status === "error" ? result.message : `Pairing ${result.status}`,
      },
    });
  }
  if (result.scope === "persistent") {
    await store.set(device.id, device.ip, device.port, result.token);
  } else {
    getSessionCache().set(device.id, device.ip, device.port, result.token);
  }
  return {
    content: [
      {
        type: "text" as const,
        text: JSON.stringify({
          success: true,
          deviceId: device.id,
          deviceName: device.name,
          host: device.ip,
          port: device.port,
          scope: result.scope,
          persisted: result.scope === "persistent",
        }),
      },
    ],
  };
}

function describeTool(description: string, platforms?: readonly string[]): string {
  if (!platforms) {
    return description;
  }
  if (platforms.length === 0) {
    return `${description} Not supported on any platform yet — every native handler returns PLATFORM_NOT_SUPPORTED.`;
  }
  return `${description} Platforms: ${platforms.join(", ")}.`;
}

function getFilteredDevices(params: Record<string, unknown>): DiscoveredDevice[] {
  return filterDevices(getAllDevices(), {
    platform: params.platform as Platform | undefined,
    include: params.include as string | undefined,
    exclude: params.exclude as string | undefined,
  });
}
