#!/usr/bin/env node
// OpenAI-compatible PROTOCOL FIXTURE — not an inference server.
//
// Deterministic, dependency-free (Node >= 18) stand-in for llama-server,
// LM Studio, vLLM and friends, used to verify Kelpie's endpoint client:
// model discovery, auth, health states, and a deliberately hostile SSE
// stream (tiny chunks split inside JSON, inside "data:" and inside multibyte
// UTF-8; keep-alive comments; a role-only first delta; fragmented tool-call
// arguments; reasoning deltas; a usage frame with empty choices; [DONE]).
//
// Contract: docs/api/ai-endpoints.md.
// Usage and the control API: README.md next to this file.

import { createServer } from "node:http";
import { parseArgs } from "node:util";
import { realpathSync } from "node:fs";
import { pathToFileURL } from "node:url";

export const FIXTURE_MODEL = "fixture-protocol-1";
export const STATES = ["ready", "loading", "auth", "busy", "malformed", "empty", "nodiscovery", "hang"];

/** Order in which the fixture picks a tool to call from the request's `tools`. */
export const TOOL_PREFERENCE = [
  "get_page_text",
  "get_current_url",
  "get_visible_elements",
  "find_element",
  "get_accessibility_tree",
  "get_form_state",
  "wait_for_element",
];

/** Arguments per tool, shaped like docs/plans/…-openai-compatible-endpoints.md "Agent tool loop". */
const TOOL_ARGUMENTS = {
  get_page_text: { selector: "body" },
  get_current_url: {},
  get_visible_elements: { interactableOnly: true },
  find_element: { text: "Příliš žluťoučký kůň 🐎" },
  get_accessibility_tree: { maxDepth: 4, interactableOnly: false },
  get_form_state: {},
  wait_for_element: { selector: "body", timeout: 1000 },
};

const REASONING_TEXT = "Přemýšlím o odpovědi… 🤔 hotovo.";
const ANSWER_SUFFIX = " — Příliš žluťoučký kůň úpěl ďábelské ódy 🦭";
const MAX_RECORDED = 200;
const NEWLINES = { lf: "\n", crlf: "\r\n", cr: "\r" };

function parseOptions(argv) {
  const { values } = parseArgs({
    args: argv,
    options: {
      port: { type: "string", default: "18990" },
      base: { type: "string", default: "/openai/v1" },
      host: { type: "string", default: "127.0.0.1" },
      "api-key": { type: "string" },
      "chunk-max": { type: "string", default: "7" },
      "chunk-delay-ms": { type: "string", default: "1" },
      newline: { type: "string", default: "lf" },
      seed: { type: "string", default: "1" },
      help: { type: "boolean", default: false },
    },
    strict: true,
  });
  const port = Number(values.port);
  const chunkMax = Number(values["chunk-max"]);
  if (!Number.isInteger(port) || port < 0 || port > 65535) throw new Error("--port must be 0-65535 (0 picks a free port)");
  if (!Number.isInteger(chunkMax) || chunkMax < 1) throw new Error("--chunk-max must be a positive integer");
  if (!(values.newline in NEWLINES)) throw new Error("--newline must be lf, crlf or cr");
  const base = `/${values.base.replace(/^\/+|\/+$/g, "")}`.replace(/^\/$/, "");
  return {
    help: values.help,
    port,
    base,
    host: values.host,
    apiKey: values["api-key"],
    chunkMax,
    chunkDelayMs: Math.max(0, Number(values["chunk-delay-ms"]) || 0),
    newline: NEWLINES[values.newline],
    seed: Number(values.seed) || 1,
  };
}

/** Small deterministic PRNG (mulberry32) so chunk boundaries are reproducible. */
function prng(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * Cut `bytes` into pieces of 1…chunkMax bytes, always cutting inside every
 * "data:" field name and after the first byte of every multibyte UTF-8
 * sequence, so a client that decodes per chunk or matches "data:" per chunk
 * is guaranteed to break.
 */
export function chunkBytes(bytes, chunkMax, random) {
  const forced = new Set();
  const marker = Buffer.from("data:");
  for (let at = bytes.indexOf(marker); at !== -1; at = bytes.indexOf(marker, at + 1)) forced.add(at + 2);
  for (let i = 0; i < bytes.length; i += 1) if (bytes[i] >= 0xc0) forced.add(i + 1);
  const chunks = [];
  let start = 0;
  while (start < bytes.length) {
    let end = Math.min(bytes.length, start + 1 + Math.floor(random() * chunkMax));
    for (let i = start + 1; i < end; i += 1) {
      if (forced.has(i)) { end = i; break; }
    }
    chunks.push(bytes.subarray(start, end));
    start = end;
  }
  return chunks;
}

function splitText(text, size) {
  const parts = [];
  const chars = Array.from(text);
  for (let i = 0; i < chars.length; i += size) parts.push(chars.slice(i, i + size).join(""));
  return parts;
}

function pickTool(tools) {
  const names = tools.map((tool) => tool?.function?.name).filter((name) => typeof name === "string");
  return TOOL_PREFERENCE.find((name) => names.includes(name)) ?? names[0];
}

function lastToolContent(messages) {
  const tool = [...messages].reverse().find((message) => message?.role === "tool");
  const content = tool?.content;
  if (typeof content === "string") return content;
  if (Array.isArray(content)) return content.map((part) => part?.text ?? "").join("");
  return "";
}

/** What the fixture "decides" to say, independent of streaming. */
export function planReply(request) {
  const messages = Array.isArray(request.messages) ? request.messages : [];
  const tools = Array.isArray(request.tools) ? request.tools : [];
  const last = messages.at(-1);
  if (tools.length > 0 && last?.role === "user") {
    const name = pickTool(tools);
    if (name) {
      const args = JSON.stringify(TOOL_ARGUMENTS[name] ?? {});
      return { kind: "tool", toolCall: { id: "call_fixture_1", name, arguments: args }, finishReason: "tool_calls" };
    }
  }
  if (last?.role === "tool") {
    const quoted = Array.from(lastToolContent(messages)).slice(0, 80).join("");
    return { kind: "answer", reasoning: REASONING_TEXT, content: `Fixture answer: "${quoted}"${ANSWER_SUFFIX}`, finishReason: "stop" };
  }
  return { kind: "plain", reasoning: REASONING_TEXT, content: "fixture-ok", finishReason: "stop" };
}

function usageFor(request, plan) {
  const promptTokens = JSON.stringify(request.messages ?? []).length >> 2;
  const completionTokens = ((plan.content ?? "").length + (plan.toolCall?.arguments.length ?? 0)) >> 2;
  return { prompt_tokens: promptTokens, completion_tokens: completionTokens, total_tokens: promptTokens + completionTokens };
}

/** SSE text for a plan: one JSON chunk per event, comments interleaved. */
export function streamEvents(plan, request, id, newline) {
  const created = 1760000000;
  const chunk = (delta, finishReason = null) => ({
    id, object: "chat.completion.chunk", created, model: FIXTURE_MODEL,
    choices: [{ index: 0, delta, finish_reason: finishReason }],
  });
  const events = [chunk({ role: "assistant" })];
  if (plan.kind === "tool") {
    const { toolCall } = plan;
    events.push(chunk({ tool_calls: [{ index: 0, id: toolCall.id, type: "function", function: { name: toolCall.name, arguments: "" } }] }));
    for (const part of splitText(toolCall.arguments, 2)) {
      events.push(chunk({ tool_calls: [{ index: 0, function: { arguments: part } }] }));
    }
  } else {
    for (const part of splitText(plan.reasoning, 4)) events.push(chunk({ reasoning_content: part }));
    for (const part of splitText(plan.content, 5)) events.push(chunk({ content: part }));
  }
  events.push(chunk({}, plan.finishReason));
  events.push({ id, object: "chat.completion.chunk", created, model: FIXTURE_MODEL, choices: [], usage: usageFor(request, plan) });
  const nl = newline;
  const lines = [`: keep-alive${nl}${nl}`];
  events.forEach((event, index) => {
    lines.push(`data: ${JSON.stringify(event)}${nl}${nl}`);
    if (index % 3 === 1) lines.push(`: keep-alive${nl}${nl}`);
  });
  lines.push(`data: [DONE]${nl}${nl}`);
  return lines.join("");
}

function completionBody(plan, request, id) {
  const message = { role: "assistant", content: plan.kind === "tool" ? null : plan.content };
  if (plan.reasoning) message.reasoning_content = plan.reasoning;
  if (plan.toolCall) {
    message.tool_calls = [{ id: plan.toolCall.id, type: "function", function: { name: plan.toolCall.name, arguments: plan.toolCall.arguments } }];
  }
  return {
    id, object: "chat.completion", created: 1760000000, model: FIXTURE_MODEL,
    choices: [{ index: 0, message, finish_reason: plan.finishReason }],
    usage: usageFor(request, plan),
  };
}

function modelsBody(state) {
  if (state === "empty") return { object: "list", data: [] };
  return {
    object: "list",
    data: [{
      id: FIXTURE_MODEL,
      object: "model",
      created: 1760000000,
      owned_by: "kelpie-fixture",
      meta: { n_ctx: 32768 },
      architecture: { input_modalities: ["text"] },
      status: { value: "loaded" },
    }],
  };
}

function errorBody(message, type, code) {
  return { error: { message, type, code } };
}

function sendJson(response, status, body, extraHeaders = {}) {
  const text = JSON.stringify(body);
  response.writeHead(status, { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(text), ...extraHeaders });
  response.end(text);
}

function readBody(request) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    request.on("data", (chunk) => chunks.push(chunk));
    request.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    request.on("error", reject);
  });
}

function parseJson(text) {
  try { return text ? JSON.parse(text) : undefined; } catch { return undefined; }
}

function recordedHeaders(headers) {
  const recorded = { ...headers };
  recorded.authorization = headers.authorization ? "present" : "absent";
  return recorded;
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export function createFixture(options) {
  const fixture = { state: "ready", requests: [], counter: 0 };
  const random = prng(options.seed);
  const sockets = new Set();

  async function writeChunked(response, text, contentType) {
    response.writeHead(200, { "Content-Type": contentType, "Cache-Control": "no-cache", Connection: "keep-alive" });
    response.flushHeaders();
    for (const piece of chunkBytes(Buffer.from(text, "utf8"), options.chunkMax, random)) {
      if (response.destroyed) return;
      response.write(piece);
      // 0 still yields to the event loop so every piece leaves as its own write.
      await (options.chunkDelayMs > 0 ? sleep(options.chunkDelayMs) : new Promise((resolve) => setImmediate(resolve)));
    }
    response.end();
  }

  function authorised(request) {
    if (!options.apiKey) return true;
    return request.headers.authorization === `Bearer ${options.apiKey}`;
  }

  /** Shared state gates for every API route; returns true when it answered. */
  function stateGate(response) {
    switch (fixture.state) {
      case "hang": return true; // never answer; the client's timeout must fire
      case "auth": sendJson(response, 401, errorBody("Invalid API key", "invalid_request_error", "invalid_api_key")); return true;
      case "loading": sendJson(response, 503, errorBody("Loading model", "unavailable_error", 503)); return true;
      case "busy": sendJson(response, 429, errorBody("Server busy, retry shortly", "server_busy", 429), { "Retry-After": "1" }); return true;
      case "malformed":
        response.writeHead(200, { "Content-Type": "text/html" });
        response.end("<html><body>definitely not json</body></html>");
        return true;
      default: return false;
    }
  }

  async function chat(request, response, body) {
    if (!body || typeof body !== "object") {
      sendJson(response, 400, errorBody("Request body must be JSON", "invalid_request_error", "invalid_json"));
      return;
    }
    if (body.model !== undefined && body.model !== FIXTURE_MODEL) {
      sendJson(response, 404, errorBody(`model '${String(body.model)}' not found`, "invalid_request_error", "model_not_found"));
      return;
    }
    fixture.counter += 1;
    const id = `chatcmpl-fixture-${fixture.counter}`;
    const plan = planReply(body);
    if (body.stream === true) {
      await writeChunked(response, streamEvents(plan, body, id, options.newline), "text/event-stream; charset=utf-8");
      return;
    }
    await writeChunked(response, JSON.stringify(completionBody(plan, body, id)), "application/json");
  }

  async function api(request, response, route, body) {
    if (!authorised(request)) {
      sendJson(response, 401, errorBody("Missing or invalid API key", "invalid_request_error", "invalid_api_key"));
      return;
    }
    if (stateGate(response)) return;
    if (request.method === "GET" && route === "/models") {
      if (fixture.state === "nodiscovery") {
        sendJson(response, 404, errorBody("Not found", "not_found_error", 404));
        return;
      }
      sendJson(response, 200, modelsBody(fixture.state));
      return;
    }
    if (request.method === "POST" && route === "/chat/completions") {
      await chat(request, response, body);
      return;
    }
    sendJson(response, 404, errorBody(`No route ${request.method} ${route}`, "not_found_error", 404));
  }

  async function control(request, response, path) {
    if (path === "/__fixture/state" && request.method === "GET") {
      sendJson(response, 200, { state: fixture.state, states: STATES });
      return;
    }
    if (path === "/__fixture/state" && request.method === "POST") {
      const body = parseJson(await readBody(request));
      if (!STATES.includes(body?.state)) {
        sendJson(response, 400, { error: `state must be one of ${STATES.join(", ")}` });
        return;
      }
      fixture.state = body.state;
      sendJson(response, 200, { state: fixture.state });
      return;
    }
    if (path === "/__fixture/requests" && request.method === "GET") {
      sendJson(response, 200, { requests: fixture.requests });
      return;
    }
    if (path === "/__fixture/requests" && request.method === "DELETE") {
      fixture.requests = [];
      sendJson(response, 200, { requests: [] });
      return;
    }
    sendJson(response, 404, { error: `No fixture route ${request.method} ${path}` });
  }

  const server = createServer(async (request, response) => {
    const path = new URL(request.url ?? "/", "http://fixture.invalid").pathname;
    try {
      if (path.startsWith("/__fixture/")) {
        await control(request, response, path);
        return;
      }
      const raw = await readBody(request);
      const body = parseJson(raw);
      fixture.requests.push({ method: request.method, path, headers: recordedHeaders(request.headers), body: body ?? (raw || null) });
      if (fixture.requests.length > MAX_RECORDED) fixture.requests.shift();
      if (path !== options.base && !path.startsWith(`${options.base}/`)) {
        sendJson(response, 404, errorBody(`Outside base path ${options.base}`, "not_found_error", 404));
        return;
      }
      await api(request, response, path.slice(options.base.length) || "/", body);
    } catch (error) {
      if (!response.headersSent) sendJson(response, 500, errorBody(String(error?.message ?? error), "fixture_error", 500));
      else response.destroy();
    }
  });
  server.on("connection", (socket) => {
    socket.setNoDelay(true);
    sockets.add(socket);
    socket.on("close", () => sockets.delete(socket));
  });

  return {
    server,
    fixture,
    close: () => new Promise((resolve) => {
      for (const socket of sockets) socket.destroy();
      server.close(() => resolve());
    }),
  };
}

const USAGE = `Usage: node server.mjs [--port 18990] [--base /openai/v1] [--host 127.0.0.1]
                      [--api-key KEY] [--chunk-max 7] [--chunk-delay-ms 1]
                      [--newline lf|crlf|cr] [--seed 1]
PROTOCOL FIXTURE for Kelpie's OpenAI-compatible endpoint client — not an inference server.
--port 0 picks a free port. See README.md for the /__fixture control API.`;

async function main() {
  let options;
  try {
    options = parseOptions(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`${error.message}\n${USAGE}\n`);
    process.exit(2);
  }
  if (options.help) {
    process.stdout.write(`${USAGE}\n`);
    return;
  }
  const { server, close } = createFixture(options);
  server.listen(options.port, options.host, () => {
    const { port } = server.address();
    const host = options.host.includes(":") ? `[${options.host}]` : options.host;
    process.stdout.write(`fixture listening on http://${host}:${port}${options.base}\n`);
  });
  const stop = () => { close().then(() => process.exit(0)); };
  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);
}

if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
  await main();
}
