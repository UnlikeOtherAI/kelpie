/**
 * JSON-RPC 2.0 envelope validation.
 *
 * The MCP SDK trusts its inputs; for the HTTP transport we sit in front of it
 * and reject malformed envelopes with the spec error code -32600 (Invalid
 * Request) before they reach the SDK. This catches accidental misuse and
 * blocks unrelated JSON traffic from being interpreted as MCP messages.
 *
 * Spec: https://www.jsonrpc.org/specification
 */

export const INVALID_REQUEST_CODE = -32600;
export const PARSE_ERROR_CODE = -32700;

export interface JsonRpcError {
  code: number;
  message: string;
}

export interface JsonRpcErrorResponse {
  jsonrpc: "2.0";
  id: string | number | null;
  error: JsonRpcError;
}

export type ValidationResult =
  | { ok: true }
  | { ok: false; error: JsonRpcError; id: string | number | null };

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isValidId(value: unknown): value is string | number | null {
  if (value === null) return true;
  if (typeof value === "string") return true;
  // JSON-RPC 2.0 forbids fractional numeric ids; accept integers only.
  return typeof value === "number" && Number.isFinite(value) && Number.isInteger(value);
}

function extractId(envelope: Record<string, unknown>): string | number | null {
  const id = envelope.id;
  return isValidId(id) ? id : null;
}

/**
 * Validate a single JSON-RPC 2.0 envelope. The envelope may be a request,
 * notification, response, or error response.
 */
export function validateEnvelope(value: unknown): ValidationResult {
  if (!isPlainObject(value)) {
    return {
      ok: false,
      id: null,
      error: { code: INVALID_REQUEST_CODE, message: "Invalid Request: envelope must be a JSON object" },
    };
  }

  if (value.jsonrpc !== "2.0") {
    return {
      ok: false,
      id: extractId(value),
      error: { code: INVALID_REQUEST_CODE, message: "Invalid Request: jsonrpc must be the string \"2.0\"" },
    };
  }

  const hasMethod = "method" in value;
  const hasResult = "result" in value;
  const hasError = "error" in value;
  const hasId = "id" in value;

  // Response or error response: must have id (may be null for parse errors),
  // and exactly one of result/error.
  if (!hasMethod) {
    if (!hasId) {
      return {
        ok: false,
        id: null,
        error: { code: INVALID_REQUEST_CODE, message: "Invalid Request: response envelope missing id" },
      };
    }
    if (!isValidId(value.id)) {
      return {
        ok: false,
        id: null,
        error: { code: INVALID_REQUEST_CODE, message: "Invalid Request: id must be a string, integer, or null" },
      };
    }
    if (hasResult === hasError) {
      return {
        ok: false,
        id: extractId(value),
        error: { code: INVALID_REQUEST_CODE, message: "Invalid Request: response must contain exactly one of result or error" },
      };
    }
    if (hasError && !isPlainObject(value.error)) {
      return {
        ok: false,
        id: extractId(value),
        error: { code: INVALID_REQUEST_CODE, message: "Invalid Request: error must be a JSON object" },
      };
    }
    if (hasError) {
      const errObj = value.error as Record<string, unknown>;
      if (typeof errObj.code !== "number" || !Number.isInteger(errObj.code) || typeof errObj.message !== "string") {
        return {
          ok: false,
          id: extractId(value),
          error: { code: INVALID_REQUEST_CODE, message: "Invalid Request: error must have integer code and string message" },
        };
      }
    }
    return { ok: true };
  }

  // Request or notification: method is required and must be a string.
  if (typeof value.method !== "string") {
    return {
      ok: false,
      id: extractId(value),
      error: { code: INVALID_REQUEST_CODE, message: "Invalid Request: method must be a string" },
    };
  }

  // If id is present, it must be string/number/null. Notifications omit id.
  if (hasId && !isValidId(value.id)) {
    return {
      ok: false,
      id: null,
      error: { code: INVALID_REQUEST_CODE, message: "Invalid Request: id must be a string, integer, or null" },
    };
  }

  // params, if present, must be a structured value (object or array).
  if ("params" in value && !isPlainObject(value.params) && !Array.isArray(value.params)) {
    return {
      ok: false,
      id: extractId(value),
      error: { code: INVALID_REQUEST_CODE, message: "Invalid Request: params must be an array or object" },
    };
  }

  return { ok: true };
}

/**
 * Validate a payload that may be a single envelope or a batch (array) of
 * envelopes. Returns the first validation error encountered, or { ok: true }.
 */
export function validatePayload(value: unknown): ValidationResult {
  if (Array.isArray(value)) {
    if (value.length === 0) {
      return {
        ok: false,
        id: null,
        error: { code: INVALID_REQUEST_CODE, message: "Invalid Request: batch must not be empty" },
      };
    }
    for (const entry of value) {
      const result = validateEnvelope(entry);
      if (!result.ok) return result;
    }
    return { ok: true };
  }
  return validateEnvelope(value);
}

export function makeErrorResponse(id: string | number | null, error: JsonRpcError): JsonRpcErrorResponse {
  return { jsonrpc: "2.0", id, error };
}
