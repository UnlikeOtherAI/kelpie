import { API_VERSION_PREFIX } from "@unlikeotherai/kelpie-shared";
import type {
  PairRequest,
  PairResponse,
  PairScope,
  PairStatusResponse,
} from "@unlikeotherai/kelpie-shared";

/**
 * Client-side state machine for `POST /v1/pair` + `GET /v1/pair/status` polling.
 *
 * Caller is responsible for persisting (or not) the returned token according
 * to the issued `scope`:
 *   - `session`    -> {@link SessionTokenCache} (in-memory)
 *   - `persistent` -> {@link TokenStore} (disk)
 */

export interface PairOutcome {
  status: "approved";
  scope: PairScope;
  token: string;
  requestId: string;
}

export type PairFailure =
  | { status: "denied"; requestId: string }
  | { status: "expired"; requestId: string }
  | { status: "not_found"; requestId: string }
  | { status: "error"; code: string; message: string };

export type PairResult = PairOutcome | PairFailure;

export interface PairContext {
  /** Used to construct the URL — string forms IPv4 or bracketed IPv6. */
  host: string;
  port: number;
  /** Stable per-install UUID. */
  clientId: string;
  /** Self-reported human label. Server sanitizes — we still pass the truth. */
  clientName: string;
  /**
   * Per-request timeout for individual HTTP calls in ms. Polling continues
   * until `overallTimeoutMs` regardless.
   */
  perRequestTimeoutMs?: number;
  /** Total time before we give up polling, in ms. Defaults to 5 min. */
  overallTimeoutMs?: number;
  /** Polling cadence, in ms. Defaults to 1 s. */
  pollIntervalMs?: number;
  /** Side-effect hook (e.g. CLI progress dot). */
  onPending?: (info: { requestId: string; attempt: number }) => void;
}

const DEFAULT_REQUEST_TIMEOUT_MS = 10_000;
const DEFAULT_OVERALL_TIMEOUT_MS = 5 * 60_000;
const DEFAULT_POLL_INTERVAL_MS = 1_000;

function buildUrl(host: string, port: number, path: string): string {
  const bracketed = host.includes(":") && !host.startsWith("[") ? `[${host}]` : host;
  return `http://${bracketed}:${port}${path}`;
}

interface FetchJsonResult {
  ok: boolean;
  status: number;
  data: unknown;
  error?: string;
}

async function fetchJson(
  url: string,
  init: RequestInit,
  timeoutMs: number,
): Promise<FetchJsonResult> {
  const controller = new AbortController();
  const timer = setTimeout(() => {
    controller.abort();
  }, timeoutMs);
  try {
    const response = await fetch(url, { ...init, signal: controller.signal });
    let data: unknown = null;
    try {
      data = await response.json();
    } catch {
      data = null;
    }
    return { ok: response.ok, status: response.status, data };
  } catch (err) {
    if (err instanceof DOMException && err.name === "AbortError") {
      return { ok: false, status: 408, data: null, error: "Request timed out" };
    }
    return {
      ok: false,
      status: 0,
      data: null,
      error: err instanceof Error ? err.message : "Network error",
    };
  } finally {
    clearTimeout(timer);
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Issue `POST /v1/pair` and return the server's pending acknowledgement.
 *
 * The CLI shows `requestId` / `expiresAt` to the user so they know how long
 * the device prompt is valid.
 */
export async function requestPair(ctx: PairContext): Promise<
  | { ok: true; pending: PairResponse }
  | { ok: false; code: string; message: string }
> {
  const body: PairRequest = { clientId: ctx.clientId, clientName: ctx.clientName };
  const result = await fetchJson(
    buildUrl(ctx.host, ctx.port, `${API_VERSION_PREFIX}pair`),
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    },
    ctx.perRequestTimeoutMs ?? DEFAULT_REQUEST_TIMEOUT_MS,
  );

  if (result.ok && isPairResponse(result.data)) {
    return { ok: true, pending: result.data };
  }

  const errorPayload = extractError(result.data);
  return {
    ok: false,
    code: errorPayload?.code ?? (result.status === 403 ? "DENIED" : "PAIR_FAILED"),
    message:
      errorPayload?.message ??
      result.error ??
      `Pair request failed with status ${result.status}`,
  };
}

function isPairResponse(data: unknown): data is PairResponse {
  if (!data || typeof data !== "object") return false;
  return "requestId" in data && typeof (data as { requestId: unknown }).requestId === "string";
}

function isPairStatusResponse(data: unknown): data is PairStatusResponse {
  if (!data || typeof data !== "object") return false;
  return "status" in data && typeof (data as { status: unknown }).status === "string";
}

function extractError(data: unknown): { code?: string; message?: string } | null {
  if (!data || typeof data !== "object") return null;
  const err = (data as { error?: unknown }).error;
  if (!err || typeof err !== "object") return null;
  const { code, message } = err as { code?: unknown; message?: unknown };
  return {
    code: typeof code === "string" ? code : undefined,
    message: typeof message === "string" ? message : undefined,
  };
}

/**
 * Poll `GET /v1/pair/status?requestId=…` until the request reaches a terminal
 * state or {@link PairContext.overallTimeoutMs} elapses.
 */
export async function pollPairStatus(
  ctx: PairContext,
  requestId: string,
): Promise<PairResult> {
  const deadline = Date.now() + (ctx.overallTimeoutMs ?? DEFAULT_OVERALL_TIMEOUT_MS);
  const interval = ctx.pollIntervalMs ?? DEFAULT_POLL_INTERVAL_MS;
  let attempt = 0;

  while (Date.now() < deadline) {
    attempt += 1;
    const url = buildUrl(
      ctx.host,
      ctx.port,
      `${API_VERSION_PREFIX}pair/status?requestId=${encodeURIComponent(requestId)}`,
    );
    const result = await fetchJson(
      url,
      { method: "GET" },
      ctx.perRequestTimeoutMs ?? DEFAULT_REQUEST_TIMEOUT_MS,
    );

    if (result.ok && isPairStatusResponse(result.data)) {
      const state = result.data.status;
      if (state === "approved" && result.data.token && result.data.scope) {
        return {
          status: "approved",
          scope: result.data.scope,
          token: result.data.token,
          requestId,
        };
      }
      if (state === "denied" || state === "expired" || state === "not_found") {
        return { status: state, requestId };
      }
      ctx.onPending?.({ requestId, attempt });
    } else if (result.status === 0 || result.status === 408) {
      // Transient — fall through to retry.
      ctx.onPending?.({ requestId, attempt });
    } else {
      return {
        status: "error",
        code: `HTTP_${result.status}`,
        message: result.error ?? `Status poll returned ${result.status}`,
      };
    }

    await sleep(interval);
  }

  return { status: "expired", requestId };
}

/** Convenience: issue + poll in one call. */
export async function pair(ctx: PairContext): Promise<PairResult> {
  const initial = await requestPair(ctx);
  if (!initial.ok) {
    return { status: "error", code: initial.code, message: initial.message };
  }
  return pollPairStatus(ctx, initial.pending.requestId);
}

/**
 * Strip bearer-shaped material from a log line. Applied to anything the CLI
 * prints to stderr/stdout that comes from the network.
 *
 * Replaces:
 *  - `Authorization: Bearer <…>` header values
 *  - JSON `"token"` / `"bearer"` field values
 *  - raw runs of 40+ base64url chars (catches bare bearer leaks)
 */
export function redact(input: string): string {
  if (!input) return input;
  let out = input;
  out = out.replace(/(authorization\s*:\s*bearer\s+)([^\s]+)/gi, "$1[redacted]");
  out = out.replace(/("(?:token|bearer)"\s*:\s*")([^"]+)(")/gi, "$1[redacted]$3");
  out = out.replace(/\b[A-Za-z0-9_-]{40,}\b/g, "[redacted]");
  return out;
}

/** Redact every string value in a JSON-shaped object. Returns a new value. */
export function redactObject(value: unknown): unknown {
  if (typeof value === "string") return redact(value);
  if (Array.isArray(value)) return value.map((v) => redactObject(v));
  if (value && typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      if (k === "token" || k === "bearer") {
        out[k] = "[redacted]";
      } else {
        out[k] = redactObject(v);
      }
    }
    return out;
  }
  return value;
}
