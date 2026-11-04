import test from "node:test";
import assert from "node:assert/strict";
import { connect } from "node:net";
import { Agent, get } from "node:http";
import { once } from "node:events";
import { startCaptureFixture } from "./fixture-server.mjs";

test("fixture close drains preconnect keepalive and partial POST idempotently", async () => {
  const fixture = await startCaptureFixture();
  const port = Number(new URL(fixture.url).port);
  const raw = connect({ host: "127.0.0.1", port });
  const partial = connect({ host: "127.0.0.1", port });
  await Promise.all([once(raw, "connect"), once(partial, "connect")]);
  raw.on("error", () => {}); partial.on("error", () => {});
  partial.write("POST /events HTTP/1.1\r\nHost: fixture\r\nContent-Length: 64\r\n\r\n{");
  const agent = new Agent({ keepAlive: true });
  await new Promise((resolve, reject) => {
    get(fixture.url, { agent }, response => { response.resume(); response.once("end", resolve); }).once("error", reject);
  });
  await new Promise(resolve => setTimeout(resolve, 10));
  const first = fixture.close();
  assert.equal(fixture.close(), first);
  const timeout = new Promise((_, reject) => { const timer = setTimeout(() => reject(new Error("fixture shutdown exceeded 1s")), 1000); timer.unref(); });
  await Promise.race([first, timeout]);
  assert.equal(fixture.close(), first);
  await fixture.close();
  agent.destroy(); raw.destroy(); partial.destroy();
  // A fresh server can be used immediately; no global socket registry survives.
  const next = await startCaptureFixture();
  await next.close();
});
