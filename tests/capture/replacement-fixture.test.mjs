import assert from "node:assert/strict";
import { test } from "node:test";
import { randomUUID } from "node:crypto";
import { startReplacementFixture } from "./replacement-fixture.mjs";

test("fixed replacement command uses only the owned ready document channel", { timeout: 3000 }, async () => {
  const fixture = await startReplacementFixture(), documentId = randomUUID();
  let reader;
  try {
    assert.throws(() => fixture.replaceNext(documentId), /owned document/);
    assert.equal((await fetch(fixture.url + "/control?documentId=invalid")).status, 400);
    const response = await fetch(fixture.url + "/control?documentId=" + documentId, { signal: AbortSignal.timeout(2000) });
    assert.equal(response.headers.get("content-type"), "text/event-stream");
    reader = response.body.getReader();
    let text = "";
    const through = async marker => {
      while (!text.includes(marker)) {
        const part = await reader.read(); assert.equal(part.done, false);
        text += new TextDecoder().decode(part.value);
      }
    };
    await through(": ready\n\n");
    fixture.replaceNext(documentId);
    await through("data: replace-next\n\n");
    assert.equal((await fetch(fixture.url + "/events", { method: "POST",
      body: JSON.stringify({ documentId, type: "replaced", time: 3, oldConnected: false }) })).status, 202);
    assert.equal(fixture.events.length, 1);
    assert.equal(fixture.events[0].oldConnected, false);
  } finally { await reader?.cancel(); await fixture.close(); }
});
