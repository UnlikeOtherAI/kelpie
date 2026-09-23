import { request as httpRequest } from "node:http";

import { delay } from "./process.mjs";

export function bearerHeaders(token) {
  return {
    accept: "application/json",
    authorization: `Bearer ${token}`,
    "content-type": "application/json",
  };
}

export async function rawRequest({ port, path, method = "POST", headers = {}, body = "" }) {
  return new Promise((resolve, reject) => {
    const request = httpRequest({ host: "127.0.0.1", port, path, method, headers }, response => {
      const chunks = [];
      response.on("data", chunk => chunks.push(chunk));
      response.on("end", () => {
        const text = Buffer.concat(chunks).toString("utf8");
        let json = null;
        try { json = text.length === 0 ? null : JSON.parse(text); } catch { /* caller gets raw text */ }
        resolve({ status: response.statusCode ?? 0, headers: response.headers, text, json });
      });
    });
    request.setTimeout(10_000, () => request.destroy(new Error(`${method} ${path} timed out`)));
    request.once("error", reject);
    if (body.length > 0) request.write(body);
    request.end();
  });
}

export async function control(readiness, method, body = {}) {
  const response = await rawRequest({
    port: readiness.port,
    path: `/v1/${method}`,
    headers: bearerHeaders(readiness.token),
    body: JSON.stringify(body),
  });
  if (response.status < 200 || response.status >= 300 || response.json?.success !== true) {
    throw new Error(`/${method} failed (${response.status}): ${response.text}`);
  }
  return response.json;
}

export async function expectControlError(readiness, method, body, code) {
  const response = await rawRequest({
    port: readiness.port,
    path: `/v1/${method}`,
    headers: bearerHeaders(readiness.token),
    body: JSON.stringify(body),
  });
  if (response.status < 400 || response.json?.success !== false) {
    throw new Error(`/${method} unexpectedly succeeded: ${response.text}`);
  }
  if (code !== undefined && response.json?.error?.code !== code) {
    throw new Error(`/${method} expected ${code}, received ${response.text}`);
  }
  return response.json;
}

export async function waitFor(condition, description, timeoutMs = 10_000) {
  const deadline = Date.now() + timeoutMs;
  let lastError = "condition was false";
  while (Date.now() < deadline) {
    try {
      const value = await condition();
      if (value) return value;
      lastError = "condition was false";
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
    }
    await delay(100);
  }
  throw new Error(`Timed out waiting for ${description}: ${lastError}`);
}

// Chromium reports the canonical URL once a load commits, so an origin-only
// fixture URL comes back with a trailing slash. Compare canonical forms.
export function sameUrl(actual, expected) {
  try {
    return new URL(actual).href === new URL(expected).href;
  } catch {
    return actual === expected;
  }
}

export function resultValue(response) {
  if (Object.hasOwn(response, "result")) return response.result;
  if (Object.hasOwn(response, "value")) return response.value;
  if (Object.hasOwn(response, "data")) return response.data;
  return response;
}

export async function mcpRequest(readiness, payload, protocolVersion = undefined) {
  const headers = {
    ...bearerHeaders(readiness.token),
    accept: "application/json, text/event-stream",
  };
  if (protocolVersion !== undefined) headers["mcp-protocol-version"] = protocolVersion;
  return rawRequest({
    port: readiness.port,
    path: readiness.mcp.endpoint,
    headers,
    body: JSON.stringify(payload),
  });
}
