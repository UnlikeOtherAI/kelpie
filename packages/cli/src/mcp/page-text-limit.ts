/**
 * A ceiling on `kelpie_get_page_text`. A real article's readable text runs to
 * tens of kilobytes (a Wikipedia page came to about 80 KB), which an agent
 * rarely needs in one piece and which an integrator's result cap may refuse
 * outright. The limit is applied here, in the MCP layer, so every platform
 * gets it from one implementation; the device HTTP API stays unbounded.
 */

export const DEFAULT_PAGE_TEXT_MAX_CHARS = 20_000;

type JsonObject = Record<string, unknown>;

/**
 * The field that carries the text: `content` on iOS, Android and macOS,
 * `text` on the desktop Chromium engine (Windows, Linux).
 */
const textFields = ["content", "text"] as const;

export function limitPageText(data: unknown, maxChars: number = DEFAULT_PAGE_TEXT_MAX_CHARS): unknown {
  if (!isJsonObject(data) || data.success !== true) return data;
  const field = textFields.find((name) => typeof data[name] === "string");
  if (!field) return data;
  const text = data[field] as string;
  if (text.length <= maxChars) return { ...data, truncated: false };
  const kept = cutWithoutSplittingPair(text, maxChars);
  return {
    ...data,
    [field]: kept,
    truncated: true,
    totalChars: text.length,
    note: `Page text truncated to ${kept.length} of ${text.length} characters. Pass a larger maxChars, or a selector for the part you need.`,
  };
}

/** Cut to at most `maxChars` UTF-16 code units, never leaving half a surrogate pair. */
function cutWithoutSplittingPair(text: string, maxChars: number): string {
  const lastKept = text.charCodeAt(maxChars - 1);
  const isHighSurrogate = lastKept >= 0xd800 && lastKept <= 0xdbff;
  return text.slice(0, isHighSurrogate ? maxChars - 1 : maxChars);
}

function isJsonObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
