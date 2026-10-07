import { spawn, type ChildProcess } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";

/**
 * Conformance test for tests/fixtures/openai-compatible/server.mjs — the
 * protocol fixture device implementations are verified against. It proves
 * the fixture really is hostile in the ways the contract needs (fragmented
 * SSE, split UTF-8, fragmented tool-call arguments) and that its scripted
 * states behave as documented.
 */

const here = dirname(fileURLToPath(import.meta.url));
const fixturePath = join(here, "..", "..", "..", "..", "tests", "fixtures", "openai-compatible", "server.mjs");
const KEY = "fixture-test-key-123";
const MODEL = "fixture-protocol-1";

interface Fixture { child: ChildProcess; origin: string; base: string }

function startFixture(args: string[]): Promise<Fixture> {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [fixturePath, "--port", "0", ...args], { stdio: ["ignore", "pipe", "pipe"] });
    let output = "";
    const timer = setTimeout(() => { child.kill(); reject(new Error(`fixture did not start: ${output}`)); }, 10_000);
    child.stdout?.on("data", (data: Buffer) => {
      output += data.toString();
      const match = /fixture listening on (http:\/\/[^/\s]+)(\S*)/.exec(output);
      if (match) {
        clearTimeout(timer);
        resolve({ child, origin: match[1], base: `${match[1]}${match[2]}` });
      }
    });
    child.stderr?.on("data", (data: Buffer) => { output += data.toString(); });
    child.on("exit", (code) => { clearTimeout(timer); reject(new Error(`fixture exited ${code}: ${output}`)); });
  });
}

// --- A small byte-oriented SSE reader (test-only) ---

interface SseEvent { data: string }
interface SseRead { reads: Uint8Array[]; comments: string[]; events: SseEvent[]; done: boolean }

function* splitLines(buffer: Buffer, final: boolean): Generator<{ line: Buffer; rest: Buffer }> {
  let start = 0;
  for (let i = 0; i < buffer.length; i += 1) {
    const byte = buffer[i];
    if (byte !== 0x0a && byte !== 0x0d) continue;
    if (byte === 0x0d && i === buffer.length - 1 && !final) break; // maybe half of \r\n
    const line = buffer.subarray(start, i);
    if (byte === 0x0d && buffer[i + 1] === 0x0a) i += 1;
    start = i + 1;
    yield { line, rest: buffer.subarray(start) };
  }
}

async function readSse(response: Response): Promise<SseRead> {
  const reader = response.body!.getReader();
  const decoder = new TextDecoder("utf-8", { fatal: true });
  const result: SseRead = { reads: [], comments: [], events: [], done: false };
  let pending = Buffer.alloc(0);
  let data: string[] = [];
  const consume = (final: boolean) => {
    for (const { line, rest } of splitLines(pending, final)) {
      pending = rest;
      const text = decoder.decode(line);
      if (text === "") {
        if (data.length > 0) {
          const joined = data.join("\n");
          if (joined === "[DONE]") result.done = true;
          else result.events.push({ data: joined });
        }
        data = [];
      } else if (text.startsWith(":")) {
        result.comments.push(text);
      } else if (text.startsWith("data:")) {
        data.push(text.slice(5).replace(/^ /, ""));
      }
    }
  };
  for (;;) {
    const { value, done } = await reader.read();
    if (done) break;
    result.reads.push(value);
    pending = Buffer.concat([pending, Buffer.from(value)]);
    consume(false);
  }
  consume(true);
  return result;
}

function isPartialUtf8Tail(bytes: Uint8Array): boolean {
  for (let back = 1; back <= Math.min(3, bytes.length); back += 1) {
    const byte = bytes[bytes.length - back];
    if (byte >= 0xc0) {
      const length = byte >= 0xf0 ? 4 : byte >= 0xe0 ? 3 : 2;
      return back < length;
    }
    if (byte < 0x80) return false;
  }
  return false;
}

function splitsInsideDataField(reads: Uint8Array[]): boolean {
  return reads.some((read, index) => {
    const next = reads[index + 1];
    return next !== undefined && Buffer.from(read).toString("latin1").endsWith("da") && Buffer.from(next).toString("latin1").startsWith("ta:");
  });
}

// --- Helpers ---

const auth = { Authorization: `Bearer ${KEY}` };

async function chat(fixture: Fixture, body: Record<string, unknown>, headers: Record<string, string> = auth): Promise<Response> {
  return fetch(`${fixture.base}/chat/completions`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "text/event-stream", ...headers },
    body: JSON.stringify(body),
  });
}

async function setState(fixture: Fixture, state: string): Promise<Response> {
  return fetch(`${fixture.origin}/__fixture/state`, { method: "POST", body: JSON.stringify({ state }) });
}

const tools = ["get_current_url", "get_page_text", "click"].map((name) => ({ type: "function", function: { name, parameters: { type: "object" } } }));

type Delta = Record<string, unknown> & { tool_calls?: { index: number; id?: string; function?: { name?: string; arguments?: string } }[] };
const deltas = (events: SseEvent[]): Delta[] => events
  .map((event) => JSON.parse(event.data) as { choices: { delta: Delta }[] })
  .flatMap((chunk) => chunk.choices.map((choice) => choice.delta));

describe("OpenAI-compatible protocol fixture", { timeout: 20_000 }, () => {
  let keyed: Fixture;
  let open: Fixture;

  beforeAll(async () => {
    [keyed, open] = await Promise.all([
      startFixture(["--api-key", KEY, "--chunk-max", "7", "--chunk-delay-ms", "0"]),
      startFixture(["--base", "/v1", "--newline", "crlf", "--chunk-delay-ms", "0"]),
    ]);
  }, 20_000);

  afterAll(() => {
    keyed.child.kill();
    open.child.kill();
  });

  beforeEach(async () => {
    await setState(keyed, "ready");
    await setState(open, "ready");
    await fetch(`${keyed.origin}/__fixture/requests`, { method: "DELETE" });
  });

  it("binds loopback and prints the base URL", () => {
    expect(keyed.base).toMatch(/^http:\/\/127\.0\.0\.1:\d+\/openai\/v1$/);
    expect(open.base).toMatch(/^http:\/\/127\.0\.0\.1:\d+\/v1$/);
  });

  it("serves the fixture model with metadata", async () => {
    const response = await fetch(`${keyed.base}/models`, { headers: auth });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      object: "list",
      data: [expect.objectContaining({
        id: MODEL,
        meta: { n_ctx: 32768 },
        architecture: { input_modalities: ["text"] },
        status: { value: "loaded" },
      })],
    });
  });

  it("requires the bearer key when configured and records only its presence", async () => {
    expect((await fetch(`${keyed.base}/models`)).status).toBe(401);
    expect((await fetch(`${keyed.base}/models`, { headers: { Authorization: "Bearer wrong" } })).status).toBe(401);
    expect((await fetch(`${keyed.base}/models`, { headers: auth })).status).toBe(200);
    expect((await fetch(`${open.base}/models`)).status).toBe(200);
    const recorded = await (await fetch(`${keyed.origin}/__fixture/requests`)).json() as { requests: { headers: Record<string, string> }[] };
    expect(recorded.requests.map((request) => request.headers.authorization)).toEqual(["absent", "present", "present"]);
    expect(JSON.stringify(recorded)).not.toContain(KEY);
    expect(JSON.stringify(recorded)).not.toContain("wrong");
  });

  it("switches states at runtime", async () => {
    const models = () => fetch(`${keyed.base}/models`, { headers: auth });
    const expectations: [string, number][] = [["loading", 503], ["auth", 401], ["busy", 429], ["nodiscovery", 404], ["ready", 200]];
    for (const [state, status] of expectations) {
      expect((await setState(keyed, state)).status).toBe(200);
      expect((await models()).status).toBe(status);
    }
    await setState(keyed, "malformed");
    const malformed = await models();
    expect(malformed.headers.get("content-type")).toContain("text/html");
    await expect(malformed.clone().json()).rejects.toThrow();
    await setState(keyed, "empty");
    expect(await (await models()).json()).toEqual({ object: "list", data: [] });
    await setState(keyed, "hang");
    await expect(fetch(`${keyed.base}/models`, { headers: auth, signal: AbortSignal.timeout(300) })).rejects.toThrow();
    expect(await (await fetch(`${keyed.origin}/__fixture/state`)).json()).toEqual(expect.objectContaining({ state: "hang" }));
    expect((await setState(keyed, "sideways")).status).toBe(400);
  });

  it("keeps answering chat when discovery is unsupported", async () => {
    await setState(keyed, "nodiscovery");
    const response = await chat(keyed, { model: MODEL, stream: false, messages: [{ role: "user", content: "hi" }] });
    expect(response.status).toBe(200);
  });

  it("streams a plain answer fragmented, with comments, usage and [DONE]", async () => {
    const stream = await readSse(await chat(keyed, { model: MODEL, stream: true, messages: [{ role: "user", content: "hi" }] }));
    expect(stream.done).toBe(true);
    expect(stream.reads.length).toBeGreaterThan(20);
    // Reads may coalesce in transit, but the fixture forces cuts inside every
    // multibyte character and every "data:", so some must survive.
    expect(stream.reads.some((read) => isPartialUtf8Tail(read))).toBe(true);
    expect(splitsInsideDataField(stream.reads)).toBe(true);
    expect(stream.comments).toContain(": keep-alive");
    const all = deltas(stream.events);
    expect(all[0]).toEqual({ role: "assistant" });
    expect(all.map((delta) => delta.content ?? "").join("")).toBe("fixture-ok");
    expect(all.map((delta) => delta.reasoning_content ?? "").join("")).toMatch(/Přemýšlím.*🤔/);
    const last = JSON.parse(stream.events.at(-1)!.data) as { choices: unknown[]; usage: { total_tokens: number } };
    expect(last.choices).toEqual([]);
    expect(last.usage.total_tokens).toBeGreaterThan(0);
  });

  it("fragments tool-call arguments that reassemble to valid JSON", async () => {
    const stream = await readSse(await chat(open, { model: MODEL, stream: true, tools, messages: [{ role: "user", content: "read the page" }] }, {}));
    expect(stream.done).toBe(true);
    const calls = deltas(stream.events).flatMap((delta) => delta.tool_calls ?? []);
    const fragments = calls.map((call) => call.function?.arguments ?? "").filter((part) => part.length > 0);
    expect(fragments.length).toBeGreaterThan(3);
    expect(fragments.some((part) => { try { JSON.parse(part); return false; } catch { return true; } })).toBe(true);
    expect(calls[0]).toEqual(expect.objectContaining({ index: 0, id: "call_fixture_1", function: { name: "get_page_text", arguments: "" } }));
    expect(JSON.parse(fragments.join(""))).toEqual({ selector: "body" });
    const finish = stream.events.map((event) => JSON.parse(event.data) as { choices: { finish_reason: string | null }[] })
      .flatMap((chunk) => chunk.choices.map((choice) => choice.finish_reason)).filter(Boolean);
    expect(finish).toEqual(["tool_calls"]);
  });

  it("answers a tool result by quoting it, with reasoning kept separate", async () => {
    const page = "Example Domain. This domain is for use in illustrative examples in documents. You may use it freely.";
    const stream = await readSse(await chat(keyed, {
      model: MODEL, stream: true, tools,
      messages: [
        { role: "user", content: "what is this page?" },
        { role: "assistant", content: null, tool_calls: [{ id: "call_fixture_1", type: "function", function: { name: "get_page_text", arguments: "{}" } }] },
        { role: "tool", tool_call_id: "call_fixture_1", content: page },
      ],
    }));
    const all = deltas(stream.events);
    const content = all.map((delta) => delta.content ?? "").join("");
    expect(content).toContain(page.slice(0, 80));
    expect(content).not.toContain(page.slice(0, 81));
    expect(content).toContain("🦭");
    expect(content).not.toContain("Přemýšlím");
    expect(all.map((delta) => delta.reasoning_content ?? "").join("")).toContain("Přemýšlím");
  });

  it("returns non-streaming completions and rejects unknown models", async () => {
    const response = await chat(keyed, { model: MODEL, stream: false, messages: [{ role: "user", content: "hi" }] });
    expect(await response.json()).toEqual(expect.objectContaining({
      object: "chat.completion",
      choices: [expect.objectContaining({ message: expect.objectContaining({ role: "assistant", content: "fixture-ok" }), finish_reason: "stop" })],
    }));
    expect((await chat(keyed, { model: "other-model", messages: [] })).status).toBe(404);
  });
});
