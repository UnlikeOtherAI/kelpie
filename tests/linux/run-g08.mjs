import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { resolve, join } from "node:path";
import { promisify } from "node:util";
import { startG08Fixture, g08Workflow, mapG08Scene } from "../capture/g08-fixture.mjs";

const [readinessFile, binaryFile, outputArg, runtime] = process.argv.slice(2);
assert.ok(readinessFile && binaryFile && outputArg && ["linux-osr-cef", "linux-gtk-cef"].includes(runtime));
assert.match(process.env.KELPIE_CAPTURE_SOURCE ?? "", /^[a-f0-9]{40}$/);
const output = resolve(outputArg);
await mkdir(output, { recursive: false });
const ready = JSON.parse(await readFile(readinessFile, "utf8"));
assert.equal(ready.controlMode, "loopback");
const source = process.env.KELPIE_CAPTURE_SOURCE;
const binarySHA256 = createHash("sha256").update(await readFile(binaryFile)).digest("hex");
const report = { source, testSource: process.env.KELPIE_TEST_REVISION ?? source, binarySHA256, runtime, eventsDropped: 0, cases: [] };
const api = async (method, body = {}) => {
  const response = await fetch(`http://127.0.0.1:${ready.port}/v1/${method}`, {
    method: "POST", headers: { authorization: `Bearer ${ready.token}`, "content-type": "application/json" },
    body: JSON.stringify(body), signal: AbortSignal.timeout(60000),
  });
  assert.equal(response.status, 200); return response.json();
};
const execute = promisify(execFile);
const tabs = await api("get-tabs");
const tabId = (tabs.tabs ?? tabs.result?.tabs).find(tab => tab.active)?.id;
assert.equal(typeof tabId, "string");
try {
  for (const curve of ["c", "s"]) {
    const fixture = await startG08Fixture();
    try {
      const nav = await api("navigate", { tabId, url: fixture.url });
      assert.equal(nav.success, true, JSON.stringify(nav.error));
      let loaded = false;
      for (let attempt = 0; attempt < 50 && !loaded; attempt++) {
        const state = await api("evaluate", { tabId, expression:
          "document.readyState === 'complete' && !!document.querySelector('[aria-label=\"G08 Start\"]')" });
        loaded = state.success && state.result === true;
        if (!loaded) await new Promise(resolve => setTimeout(resolve, 100));
      }
      assert.ok(loaded, "G08 fixture did not become ready");
      const workflow = g08Workflow(tabId, curve);
      const result = await api("play-script", workflow);
      assert.equal(result.success, true, JSON.stringify(result.error));
      const facts = await (await fetch(new URL("/events", fixture.url))).json();
      report.eventsDropped += facts.dropped;
      const scene = mapG08Scene(facts.events);
      const entry = { curve, runId: result.runId, capture: workflow.capture, scene, artifacts: [] };
      report.cases.push(entry);
      for (const artifact of result.artifacts) {
        if (!["image/gif", "video/mp4"].includes(artifact.mimeType)) continue;
        const chunks = []; let offset = 0;
        while (offset < artifact.byteLength) {
          const chunk = await api("get-script-artifact", { runId: result.runId, artifactId: artifact.id, offset, length: 262144 });
          assert.equal(chunk.offset, offset); assert.equal(chunk.sha256, artifact.sha256);
          const bytes = Buffer.from(chunk.data, "base64"); assert.ok(bytes.length);
          chunks.push(bytes); offset += bytes.length; assert.equal(chunk.nextOffset, offset);
          assert.equal(chunk.eof, offset === artifact.byteLength);
        }
        const bytes = Buffer.concat(chunks);
        assert.equal(bytes.length, artifact.byteLength);
        assert.equal(createHash("sha256").update(bytes).digest("hex"), artifact.sha256);
        const file = join(output, `${curve}-${artifact.id}.${artifact.mimeType === "image/gif" ? "gif" : "mp4"}`);
        await writeFile(file, bytes);
        const probe = await execute("ffprobe", ["-v", "error", "-select_streams", "v:0", "-show_entries",
          "frame=best_effort_timestamp_time", "-of", "json", file], { timeout: 60000, maxBuffer: 8388608 });
        const timestamps = JSON.parse(probe.stdout).frames.map(frame => Number(frame.best_effort_timestamp_time));
        entry.artifacts.push({ ...artifact, file, timestamps });
      }
      assert.equal(entry.artifacts.length, 2);
    } finally { await fixture.close(); }
  }
} finally {
  await writeFile(join(output, "input.json"), JSON.stringify(report, null, 2));
}
