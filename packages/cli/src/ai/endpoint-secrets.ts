/**
 * API-key handling for OpenAI-compatible endpoints on the CLI/MCP side.
 *
 * A key only ever enters through an environment variable or stdin — never an
 * argv value (shell history, `ps`) and never an MCP argument (client logs).
 * Everything the CLI prints for an endpoint command passes through
 * `redactSecrets`, so a device or proxy echoing the key back cannot leak it.
 */

export const REDACTED = "[REDACTED]";

/** Field names whose string values are always masked in printed results. */
const SECRET_FIELD = /^(api[-_]?key|authorization|x-api-key)$/i;

/** Shortest value treated as a secret substring; shorter ones would mask noise. */
const MIN_SECRET_LENGTH = 4;

export class ApiKeyInputError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ApiKeyInputError";
  }
}

/** Read a key from a named environment variable; the variable must be set and non-empty. */
export function readApiKeyFromEnv(variable: string, env: NodeJS.ProcessEnv = process.env): string {
  const name = variable.trim();
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) {
    throw new ApiKeyInputError(`"${name}" is not a valid environment variable name.`);
  }
  const value = env[name]?.trim();
  if (!value) {
    throw new ApiKeyInputError(`Environment variable ${name} is not set or is empty.`);
  }
  return value;
}

/** Read a key from stdin (piped or typed, ending with EOF); surrounding whitespace is dropped. */
export async function readApiKeyFromStream(stream: NodeJS.ReadableStream = process.stdin): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of stream) {
    chunks.push(typeof chunk === "string" ? Buffer.from(chunk) : chunk);
  }
  const value = Buffer.concat(chunks).toString("utf8").trim();
  if (!value) throw new ApiKeyInputError("No API key was received on stdin.");
  if (/[\r\n]/.test(value)) throw new ApiKeyInputError("The API key read from stdin spans several lines.");
  return value;
}

function maskString(value: string, secrets: readonly string[]): string {
  let masked = value;
  for (const secret of secrets) {
    if (secret.length >= MIN_SECRET_LENGTH) masked = masked.split(secret).join(REDACTED);
  }
  return masked.replace(/(Bearer\s+)[^\s"',;]+/gi, `$1${REDACTED}`);
}

/**
 * Deep copy of `value` with secret-named fields masked, every known secret
 * substring replaced, and `Bearer <token>` fragments masked. `hasApiKey` and
 * similar booleans are left alone.
 */
export function redactSecrets<T>(value: T, secrets: readonly string[] = []): T {
  return redactValue(value, secrets) as T;
}

function redactValue(value: unknown, secrets: readonly string[]): unknown {
  if (typeof value === "string") return maskString(value, secrets);
  if (Array.isArray(value)) return value.map((item) => redactValue(item, secrets));
  if (value === null || typeof value !== "object") return value;
  const result: Record<string, unknown> = {};
  for (const [key, field] of Object.entries(value as Record<string, unknown>)) {
    result[key] = SECRET_FIELD.test(key) && typeof field === "string" && field.length > 0
      ? REDACTED
      : redactValue(field, secrets);
  }
  return result;
}
