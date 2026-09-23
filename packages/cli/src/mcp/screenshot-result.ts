import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";
import { randomUUID } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { pathToFileURL } from "node:url";
import { normalizeImageFormat } from "../client/screenshot-options.js";

/**
 * How a screenshot reaches an MCP client. The base64 image is sent exactly
 * once, as the `image` content item: the text item and `structuredContent`
 * carry the metadata only. A client that forwards the text to a model (or
 * measures the result) would otherwise pay for the same image three times —
 * 0.5–0.9 MB for an ordinary page.
 */

type JsonObject = Record<string, unknown>;

export type ScreenshotResult = JsonObject & {
  image: string;
  format?: unknown;
  resolution?: unknown;
  success?: unknown;
};

const screenshotMethods = new Set(["screenshot", "screenshotAnnotated"]);
const mcpScreenshotDir = join(tmpdir(), "kelpie-mcp-screenshots");

export function isScreenshotResult(method: string, data: unknown): data is ScreenshotResult {
  return (
    screenshotMethods.has(method) &&
    isJsonObject(data) &&
    data.success === true &&
    typeof data.image === "string" &&
    data.image.length > 0
  );
}

export async function formatScreenshotResult(
  method: string,
  result: ScreenshotResult,
  deviceName?: string,
): Promise<CallToolResult> {
  if (result.resolution === "native") {
    return saveNativeScreenshotResult(method, result, deviceName);
  }
  return portableScreenshotResult(result);
}

function portableScreenshotResult(result: ScreenshotResult): CallToolResult {
  const format = normalizeImageFormat(result.format);
  const mimeType = `image/${format}`;
  const { image, ...rest } = result;
  const metadata: JsonObject = { ...rest, mimeType, imageBytes: decodedByteLength(image) };
  return {
    content: [
      { type: "text", text: JSON.stringify(metadata) },
      { type: "image", data: image, mimeType },
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

/** Decoded size of a base64 string, without decoding it. */
function decodedByteLength(base64: string): number {
  const padding = base64.endsWith("==") ? 2 : base64.endsWith("=") ? 1 : 0;
  return Math.floor((base64.length * 3) / 4) - padding;
}

function slugify(value: string): string {
  const slug = value.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
  return slug.length > 0 ? slug : "screenshot";
}

function isJsonObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
