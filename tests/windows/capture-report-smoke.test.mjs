import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

test("filtered acceptance run writes its final report and cleanup state", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "kelpie-capture-report-"));
  const status = { success: true, supportedVersions: [1], state: "idle", playing: false };
  const server = createServer((request, response) => {
    const value = request.url === "/v1/get-tabs" ? { tabs: [{ id: "tab", active: true }] } :
      request.url === "/v1/get-script-status" ? status :
      request.url === "/mcp" ? { result: { content: [{ text: JSON.stringify({ ok: true, value: status }) }] } } : null;
    response.writeHead(value ? 200 : 404, { "content-type": "application/json" });
    response.end(JSON.stringify(value));
  });
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  const port = server.address().port, readiness = path.join(root, "readiness.json"), output = path.join(root, "output");
  try {
    await writeFile(readiness, JSON.stringify({ controlMode: "loopback", port, token: "fixture-token", launchId: "fixture-launch" }));
    const runner = fileURLToPath(new URL("./run-script-capture-acceptance.mjs", import.meta.url));
    await promisify(execFile)(process.execPath, [runner, readiness, output], {
      timeout: 20000, env: { ...process.env, KELPIE_CAPTURE_PORT: String(port), KELPIE_CAPTURE_CASE_FILTER: "v1 capability HTTP and MCP", KELPIE_CAPTURE_SOURCE: "fixture" },
    });
    const report = JSON.parse(await readFile(path.join(output, "report.json"), "utf8"));
    assert.equal(report.source, "fixture");
    assert.equal(report.cleanup, "closed");
    assert.equal(report.checks.length, 1);
    assert.equal(report.checks[0].name, "v1 capability HTTP and MCP");
    assert.equal(report.checks[0].passed, true);
  } finally {
    await new Promise(resolve => server.close(resolve));
    await rm(root, { recursive: true, force: true });
  }
});
test("filtered failed-status case downloads partial artifact through HTTP and MCP", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "kelpie-capture-partial-"));
  const bytes = Buffer.from("partial"), sha256 = createHash("sha256").update(bytes).digest("hex");
  const manifest = { id: "artifact", mimeType: "image/gif", byteLength: bytes.length, sha256, partial: true, width: 1, height: 1 };
  const status = { success: true, supportedVersions: [1], state: "failed", playing: false, runId: "run", runSuccess: false, artifacts: [manifest] };
  const chunk = { success: true, runId: "run", artifactId: manifest.id, data: bytes.toString("base64"), offset: 0, nextOffset: bytes.length,
    eof: true, mimeType: manifest.mimeType, byteLength: bytes.length, sha256 };
  let plays = 0, directChunks = 0;
  const server = createServer(async (request, response) => {
    const body = []; for await (const part of request) body.push(part);
    let value;
    if (request.url === "/v1/get-tabs") value = { tabs: [{ id: "tab", active: true }] };
    else if (request.url === "/v1/navigate" || request.url === "/v1/evaluate") value = { success: true };
    else if (request.url === "/v1/get-script-artifact") value = chunk;
    else if (request.url === "/mcp") {
      const params = JSON.parse(Buffer.concat(body).toString()).params;
      const name = params.name === "kelpie_extension" ? params.arguments.name : params.name;
      let result;
      if (name === "kelpie_get_script_status") result = status;
      else if (name === "kelpie_get_script_artifact") { directChunks++; result = chunk; }
      else if (name === "kelpie_play_script") result = ++plays === 1 ? { success: false } : { success: true, runId: "recovery" };
      value = { result: { content: [{ text: JSON.stringify({ ok: true, value: result }) }] } };
    }
    response.writeHead(value ? 200 : 404, { "content-type": "application/json" });
    response.end(JSON.stringify(value ?? null));
  });
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  const port = server.address().port, readiness = path.join(root, "readiness.json"), output = path.join(root, "output");
  try {
    await writeFile(readiness, JSON.stringify({ controlMode: "loopback", port, token: "fixture-token", launchId: "fixture-launch" }));
    const runner = fileURLToPath(new URL("./run-script-capture-acceptance.mjs", import.meta.url));
    await promisify(execFile)(process.execPath, [runner, readiness, output], {
      timeout: 20000, env: { ...process.env, KELPIE_CAPTURE_PORT: String(port),
        KELPIE_CAPTURE_CASE_FILTER: "MCP failed status preserves partial artifacts and recovery", KELPIE_CAPTURE_SOURCE: "fixture" },
    });
    const report = JSON.parse(await readFile(path.join(output, "report.json"), "utf8"));
    assert.equal(report.cleanup, "closed"); assert.equal(report.checks.length, 1); assert.equal(report.checks[0].passed, true);
    assert.equal(directChunks, 1); assert.deepEqual(await readFile(path.join(output, "artifact.gif")), bytes);
  } finally {
    await new Promise(resolve => server.close(resolve));
    await rm(root, { recursive: true, force: true });
  }
});