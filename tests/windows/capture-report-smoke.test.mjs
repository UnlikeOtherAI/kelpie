import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
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