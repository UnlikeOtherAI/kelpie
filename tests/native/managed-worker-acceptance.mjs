// Real, disposable worker/session acceptance. Build shared first.
// Chromium: node tests/native/managed-worker-acceptance.mjs
// LP: set KELPIE_TEST_LIGHTPANDA_CDP to the operator-owned loopback test worker.
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { performance } from "node:perf_hooks";
import { allocateManagedBrowserSession } from "../../packages/shared/dist/browser-control/managed-session.js";

const require = createRequire(new URL("../../packages/shared/package.json", import.meta.url));
const { chromium } = require("playwright-core");
const fixture = createServer((req, res) => {
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.end(`<!doctype html><html><head><title>Owned fixture</title>
    <meta property="og:site_name" content="Fixture publisher"></head><body>
    <main><h1>Public heading</h1><p>Public fixture facts.</p>
    <input value="PRIVATE_INPUT"><textarea>PRIVATE_TEXTAREA</textarea>
    <div contenteditable="true">PRIVATE_EDITOR</div>
    <p hidden>HIDDEN_FIXTURE</p><button>Continue</button></main></body></html>`);
});
await new Promise((resolve) => fixture.listen(0, "127.0.0.1", resolve));
const baseUrl = `http://127.0.0.1:${fixture.address().port}`;
const endpoint = process.env.KELPIE_TEST_LIGHTPANDA_CDP;
if (endpoint) {
  const parsed = new URL(endpoint);
  assert.ok(["ws:", "http:"].includes(parsed.protocol));
  assert.ok(["127.0.0.1", "localhost", "[::1]"].includes(parsed.hostname), "Test worker must be loopback");
  assert.equal(parsed.username + parsed.password, "");
}
const backendName = endpoint ? "lightpanda" : "playwright";
const browser = endpoint ? await chromium.connectOverCDP(endpoint) : await chromium.launch({ headless: true, chromiumSandbox: true, ...(process.env.KELPIE_TEST_CHROMIUM ? { executablePath: process.env.KELPIE_TEST_CHROMIUM } : {}) });
const evidence = { backend: backendName, revision: process.env.KELPIE_TEST_REVISION ?? "unrecorded", tests: [], timingsMs: {} };
const sessions = [];
const started = performance.now();
const allowed = (url) => url.origin === baseUrl;
const make = async (isolation = "isolated", sharedContext, ttlMs = 300_000) => {
  const value = await allocateManagedBrowserSession({
    browser, backend: backendName, owner: "fixture-owner", authorize() {},
    options: { isolation, ttlMs }, sharedContext,
    network: { boundary: "operator-enforced", allowNavigation: allowed },
    // This operator fixture exercises these candidates, not a universal LP profile.
    verifiedLightpandaMethods: ["tabs.list", "tabs.new", "tabs.close", "tab.goto", "tab.url", "tab.title", "tab.reload"],
  });
  sessions.push(value);
  return value;
};
const call = async (session, method, params = {}, tabId = session.describe().ownedTabIds[0]) => {
  const response = await session.transport.call({ version: 1, method, params, tabId });
  assert.equal(response.ok, true, JSON.stringify(response));
  return response.value;
};
try {
  const first = await make();
  const second = await make();
  await call(first, "tab.goto", { url: baseUrl });
  await call(second, "tab.goto", { url: baseUrl });
  assert.equal(await call(first, "tab.title"), "Owned fixture");
  assert.equal(await call(first, "tab.url"), baseUrl + "/");
  const firstId = first.describe().ownedTabIds[0];
  const secondId = second.describe().ownedTabIds[0];
  const foreign = await first.transport.call({ version: 1, method: "tab.url", tabId: secondId, params: {} });
  assert.equal(foreign.ok, false);
  assert.equal(foreign.error.code, "TAB_NOT_FOUND");
  const contexts = browser.contexts();
  const firstPage = contexts.flatMap((context) => context.pages()).find((page) => page.url() === baseUrl + "/");
  assert.ok(firstPage);
  await firstPage.evaluate(() => { document.cookie = "owned_cookie=first"; localStorage.setItem("owned_storage", "first"); });
  const pages = contexts.flatMap((context) => context.pages()).filter((page) => page.url() === baseUrl + "/");
  assert.equal(pages.length, 2);
  const other = pages.find((page) => page !== firstPage);
  assert.equal(await other.evaluate(() => document.cookie), "");
  assert.equal(await other.evaluate(() => localStorage.getItem("owned_storage")), null);
  evidence.tests.push("OWN-01 isolated storage and foreign-tab refusal");

  const sharedContext = await browser.newContext({ serviceWorkers: "block", acceptDownloads: false });
  try {
    const existing = await sharedContext.newPage();
    await existing.goto(baseUrl);
    await existing.evaluate(() => { document.cookie = "shared_cookie=yes"; });
    const shared = await make("shared", sharedContext);
    await call(shared, "tab.goto", { url: baseUrl });
    assert.equal((await call(shared, "tabs.list")).length, 1);
    assert.equal(sharedContext.pages().length, 2);
    await shared.close();
    assert.equal(existing.isClosed(), false);
    assert.equal(sharedContext.pages().length, 1);
    assert.equal(await existing.evaluate(() => document.cookie), "shared_cookie=yes");
    evidence.tests.push("OWN-02 shared cookies, existing tab hidden and preserved");
  } finally { await sharedContext.close(); }

  if (endpoint) {
    const pixels = await first.transport.call({ version: 1, method: "tab.screenshot", tabId: firstId, params: {} });
    assert.equal(pixels.ok, false);
    assert.equal(pixels.error.code, "UNSUPPORTED");
    assert.equal(pixels.error.mayHaveCompleted, false);
    evidence.tests.push("LP-01 canonical pixels refused; no native/visual parity claim");
  }
  const expiring = await make("isolated", undefined, 1000);
  await new Promise((resolve) => setTimeout(resolve, 1150));
  const expired = await expiring.transport.call({ version: 1, method: "capabilities", params: {} });
  assert.equal(expired.ok, false);
  assert.equal(expired.error.code, "SESSION_CLOSED");
  assert.equal(browser.isConnected(), true);
  evidence.tests.push("OWN-01 expiration denies metadata and preserves borrowed browser");
  evidence.timingsMs.sessionCorpus = Math.round(performance.now() - started);
  evidence.tests.push(endpoint ? "LP-02 navigation/title/URL/tab lifecycle only" : "DIF-01 Chromium ownership baseline");
  if (process.env.KELPIE_TEST_ARTIFACT_DIR) {
    await mkdir(process.env.KELPIE_TEST_ARTIFACT_DIR, { recursive: true });
    await writeFile(join(process.env.KELPIE_TEST_ARTIFACT_DIR, `managed-${backendName}.json`), JSON.stringify(evidence, null, 2));
  }
  console.log(JSON.stringify(evidence, null, 2));
} finally {
  await Promise.allSettled(sessions.map((session) => session.close()));
  // This fixture owns the browser connection/process lifecycle; session disposal never does.
  await browser.close();
  await new Promise((resolve) => fixture.close(resolve));
}
