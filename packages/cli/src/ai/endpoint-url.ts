/**
 * Client-side mirror of `OpenAIEndpointURL.normalize` from
 * docs/api/ai-endpoints.md ("URL handling").
 *
 * The device stays authoritative: it re-normalises whatever the CLI sends.
 * This copy exists so a typo fails fast on the CLI or MCP host instead of
 * after a round trip, and so the CLI can say whether `localhost` will
 * resolve on the Kelpie device.
 */

export type EndpointUrlResult =
  | { ok: true; baseURL: string; loopback: boolean }
  | { ok: false; code: "INVALID_ENDPOINT_URL"; message: string };

/** Operation suffixes people paste along with the base URL, longest first. */
const OPERATION_SUFFIXES = ["/chat/completions", "/completions", "/models", "/embeddings"] as const;

const DEFAULT_BASE_PATH = "/v1";

const URL_SHAPE = /^([A-Za-z][A-Za-z0-9+.-]*):\/\/([^/]*)(\/.*)?$/;
const BRACKETED_HOST = /^\[([0-9A-Fa-f:.]+)\](?::(.*))?$/;
const PLAIN_HOST = /^([A-Za-z0-9._~-]+)(?::(.*))?$/;

function invalid(message: string): EndpointUrlResult {
  return { ok: false, code: "INVALID_ENDPOINT_URL", message };
}

/** `undefined` when absent, `null` when present but outside 1…65535. */
function parsePort(raw: string | undefined): number | null | undefined {
  if (raw === undefined) return undefined;
  if (!/^\d{1,5}$/.test(raw)) return null;
  const port = Number.parseInt(raw, 10);
  return port >= 1 && port <= 65535 ? port : null;
}

function splitAuthority(authority: string): { host: string; port: number | undefined } | string {
  if (authority.length === 0) return "The URL has no host.";
  if (authority.includes("@")) {
    return "User info (user:password@) is not allowed in an endpoint URL; configure an API key instead.";
  }
  const bracketed = BRACKETED_HOST.exec(authority);
  const match = bracketed ?? PLAIN_HOST.exec(authority);
  if (!match?.[1]) return `"${authority}" is not a valid host.`;
  const name = match[1].toLowerCase();
  const host = bracketed ? `[${name}]` : name;
  const port = parsePort(match[2]);
  if (port === null) return "The port must be a number from 1 to 65535.";
  return { host, port };
}

function trimTrailingSlashes(path: string): string {
  let trimmed = path;
  while (trimmed.endsWith("/")) trimmed = trimmed.slice(0, -1);
  return trimmed;
}

function normalisePath(rawPath: string): string {
  let path = trimTrailingSlashes(rawPath.replace(/\/{2,}/g, "/"));
  const suffix = OPERATION_SUFFIXES.find((operation) => path.endsWith(operation));
  if (suffix) path = trimTrailingSlashes(path.slice(0, -suffix.length));
  return path.length === 0 ? DEFAULT_BASE_PATH : path;
}

/** True for hosts that resolve on the device running Kelpie itself. */
export function isLoopbackHost(host: string): boolean {
  const bare = host.replace(/^\[|\]$/g, "").toLowerCase();
  return bare === "localhost" || bare === "::1" || /^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(bare);
}

export function normalizeEndpointUrl(input: string): EndpointUrlResult {
  const trimmed = input.trim();
  if (trimmed.length === 0) return invalid("The endpoint URL is empty.");
  if (trimmed.includes("?")) return invalid("Query strings are not allowed in an endpoint base URL.");
  if (trimmed.includes("#")) return invalid("Fragments are not allowed in an endpoint base URL.");
  if (/\s/.test(trimmed)) return invalid("The endpoint URL must not contain whitespace.");
  const shape = URL_SHAPE.exec(trimmed);
  if (!shape?.[1]) return invalid("The endpoint URL must look like http://host:port/v1.");
  const scheme = shape[1].toLowerCase();
  if (scheme !== "http" && scheme !== "https") {
    return invalid(`Only http:// and https:// endpoints are supported, not ${scheme}://.`);
  }
  const authority = splitAuthority(shape[2] ?? "");
  if (typeof authority === "string") return invalid(authority);
  const port = authority.port === undefined ? "" : `:${authority.port}`;
  const path = normalisePath(shape[3] ?? "");
  return {
    ok: true,
    baseURL: `${scheme}://${authority.host}${port}${path}`,
    loopback: isLoopbackHost(authority.host),
  };
}
