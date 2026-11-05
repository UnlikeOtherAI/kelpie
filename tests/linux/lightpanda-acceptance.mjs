#!/usr/bin/env node
// Bounded real Lightpanda compatibility/cost corpus. Run only in the verified unit.
import assert from "node:assert/strict";
import { spawn, execFile } from "node:child_process";
import { promisify } from "node:util";
import { createServer, createConnection } from "node:net";
import { createRequire } from "node:module";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { join, resolve } from "node:path";
import { createHash } from "node:crypto";
import { performance } from "node:perf_hooks";
import { startCaptureFixture } from "../capture/fixture-server.mjs";
import { allocateManagedBrowserSession } from "../../packages/shared/dist/browser-control/managed-session.js";
import { fixedObservationExpression } from "../../packages/shared/dist/browser-control/observation-source.js";
import { runLightpandaReaderDiagnostics } from "./lightpanda-reader-diagnostics.mjs";
const require = createRequire(new URL("../../packages/cli/package.json", import.meta.url));
const { chromium } = require("playwright-core");
const { Client } = require("@modelcontextprotocol/sdk/client/index.js");
const { StdioClientTransport, getDefaultEnvironment } = require("@modelcontextprotocol/sdk/client/stdio.js");
const executable = resolve(process.argv[2]), output = resolve(process.argv[3]);
const expected = "ae7d01d261efb9e480e18ce3424533332883863bcf70b12a4321b5733f37e19e";
const binary = await readFile(executable);
assert.equal(binary.length, 76408136);
assert.equal(createHash("sha256").update(binary).digest("hex"), expected);
await mkdir(output, { recursive: true });
const home = join(output, "empty-home"); await mkdir(home, { recursive: true });
process.env.HOME = home; process.env.KELPIE_HOME = join(home, "kelpie");
const environment = { ...process.env, LIGHTPANDA_DISABLE_TELEMETRY: "true", LIGHTPANDA_DISABLE_CORE_DUMP: "1" };
const report = { source: process.env.KELPIE_TEST_REVISION, binarySHA256: expected,
  cliBundleSource: "eee84a266ad0b3613de71eb930e1bf0c9ede8cb3",
  hostContention: "Maxis busy; one-CPU quota/CPUWeight1; no unloaded speed comparison",
  tests: [], timingsMs: {}, verifiedMethods: [], observations: {}, evaluationRequests: 0, evaluationResponseBytes: 0, publicToolRequests: 0 };
const start = performance.now(), exec = promisify(execFile);
let lp, browser, fixture, client, transport, stderr = "";
const contexts = [], sessions = [];
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function bounded(promise, ms = 4000) {
  let timer;
  try { return await Promise.race([promise, new Promise((_, reject) => { timer = setTimeout(() => reject(Error("CORPUS_TIMEOUT")), ms); })]); }
  finally { clearTimeout(timer); }
}
async function check(name, run) {
  if (performance.now() - start > 95000) throw Error("CORPUS_DEADLINE");
  const began = performance.now();
  try { const detail = await bounded(Promise.resolve().then(run), 7000); report.tests.push({ name, passed: true, detail, wallMs: performance.now() - began }); return true; }
  catch (error) { report.tests.push({ name, passed: false, error: String(error.message).slice(0, 700), wallMs: performance.now() - began }); if (error.message === "CORPUS_TIMEOUT") throw error; return false; }
}
async function evaluate(page, expression) {
  report.evaluationRequests++; const value = await bounded(page.evaluate(expression));
  report.evaluationResponseBytes += Buffer.byteLength(JSON.stringify(value) ?? "null"); return value;
}
async function alive(pid) { try { process.kill(pid, 0); return true; } catch { return false; } }
async function stop(child) {
  if (!child || child.exitCode !== null || child.signalCode !== null) return;
  const exited = new Promise(resolve => child.once("exit", resolve));
  child.kill("SIGTERM");
  try { await bounded(exited, 1500); } catch { child.kill("SIGKILL"); await bounded(exited, 1500); }
}
try {
  const group = (await readFile("/proc/self/cgroup", "utf8")).split("\n").find(line => line.startsWith("0::")).slice(3);
  const cgroup = "/sys/fs/cgroup" + group;
  report.boundary = { memoryMax: (await readFile(cgroup + "/memory.max", "utf8")).trim(),
    cpuMax: (await readFile(cgroup + "/cpu.max", "utf8")).trim(), tasksMax: (await readFile(cgroup + "/pids.max", "utf8")).trim() };
  assert.equal(report.boundary.memoryMax, "2147483648"); assert.equal(report.boundary.tasksMax, "64");
  const [quota, period] = report.boundary.cpuMax.split(/\s+/).map(Number); assert.ok(quota / period <= 1);
  const version = await exec(executable, ["version"], { env: environment, timeout: 5000, maxBuffer: 16384 });
  report.version = version.stdout.trim(); assert.match(report.version, /1\.0\.2/);
  const help = await exec(executable, ["serve", "--help"], { env: environment, timeout: 5000, maxBuffer: 32768 });
  report.serveHelp = (help.stdout + help.stderr).slice(0, 16384);
  assert.ok(report.serveHelp.includes("--host") && report.serveHelp.includes("--port"));
  fixture = await startCaptureFixture();
  const origin = new URL(fixture.url).origin;
  const reservation = createServer(); await new Promise(resolve => reservation.listen(0, "127.0.0.1", resolve));
  const port = reservation.address().port; await new Promise(resolve => reservation.close(resolve));
  const launched = performance.now();
  lp = spawn(executable, ["serve", "--host", "127.0.0.1", "--port", String(port), "--log-level", "error"], { env: environment, stdio: ["ignore", "pipe", "pipe"] });
  lp.on("error", error => { stderr = String(error.message); });
  lp.stdout.on("data", bytes => { stderr = (stderr + bytes).slice(-8192); });
  lp.stderr.on("data", bytes => { stderr = (stderr + bytes).slice(-8192); });
  let listening = false;
  for (let attempt = 0; attempt < 100 && !listening; attempt++) {
    if (lp.exitCode !== null) throw Error("LP exited before listen");
    listening = await new Promise(resolve => {
      const socket = createConnection(port, "127.0.0.1");
      socket.once("connect", () => { socket.destroy(); resolve(true); });
      socket.once("error", () => resolve(false));
    });
    if (!listening) await delay(30);
  }
  assert.ok(listening);
  const endpoint = "ws://127.0.0.1:" + port;
  browser = await chromium.connectOverCDP(endpoint, { timeout: 5000 });
  report.timingsMs.startup = performance.now() - launched; report.browserVersion = browser.version();
  const a = await browser.newContext({ serviceWorkers: "block", acceptDownloads: false }); contexts.push(a);
  const page = await a.newPage(); page.setDefaultTimeout(3000);
  let other;
  const multiplePages = await check("multiple pages in one owned context", async () => {
    other = await a.newPage(); other.setDefaultTimeout(3000);
    return { pages: a.pages().length };
  });
  const navigation = await check("cold navigation/title/url", async () => {
    await page.goto(fixture.url, { waitUntil: "domcontentloaded", timeout: 5000 });
    assert.equal(await page.title(), "Kelpie capture acceptance"); assert.equal(page.url(), new URL(fixture.url).href);
    report.verifiedMethods.push("tab.goto", "tab.title", "tab.url");
    return { title: await page.title(), url: page.url() };
  });
  if (!navigation) throw Error("Baseline navigation failed; no profile admitted");
  for (let index = 0; index < 3; index++) await check("warm navigation " + index, async () => {
    await page.goto(fixture.url, { waitUntil: "domcontentloaded", timeout: 5000 });
    assert.equal(await page.title(), "Kelpie capture acceptance"); return { title: await page.title() };
  });
  await check("raw public DOM facts (diagnostic, not canonical visibility)", async () => {
    const values = await evaluate(page, "Array.from(document.querySelectorAll('#catalogue h3'),el=>el.textContent.trim())");
    assert.deepEqual(values, ["Green tea", "Black tea"]); return { values };
  });
  await check("set synthetic cookie and local storage", async () => {
    assert.equal(await evaluate(page, "document.cookie='lp_owned=one';localStorage.setItem('lp_owned','one');true"), true);
    report.previousStateSet = true; return { syntheticStateSet: true };
  });
  const isolation = await check("concurrent isolated contexts (expected backend limit if refused)", async () => {
    const b = await browser.newContext({ serviceWorkers: "block", acceptDownloads: false }); contexts.push(b);
    const isolated = await b.newPage();
    await isolated.goto(fixture.url, { waitUntil: "domcontentloaded", timeout: 5000 });
    const value = await evaluate(isolated, "({cookie:document.cookie,storage:localStorage.getItem('lp_owned')})");
    assert.ok(!value.cookie.includes("lp_owned=one")); assert.equal(value.storage, null);
    await b.close(); return { isolated: true };
  });
  report.concurrentIsolatedContextsSupported = isolation;
  if (other) await check("explicit same-context storage sharing", async () => {
    await other.goto(fixture.url, { waitUntil: "domcontentloaded", timeout: 5000 });
    const value = await evaluate(other, "({cookie:document.cookie,storage:localStorage.getItem('lp_owned')})");
    assert.ok(value.cookie.includes("lp_owned=one")); assert.equal(value.storage, "one"); return { shared: true };
  });
  await check("install frozen hidden/private DOM adversaries", async () => {
    assert.equal(await evaluate(page, "(()=>{const box=document.createElement('div');box.innerHTML='<div hidden><h3>HIDDEN_ATTRIBUTE_LP</h3></div><div style=\"display:none\"><h3>HIDDEN_DISPLAY_LP</h3></div><div style=\"visibility:hidden\"><h3>HIDDEN_INHERITED_LP</h3></div><div contenteditable=\"true\"><h3>CAPTURE_SECRET_EDITABLE_LP</h3></div><input value=\"CAPTURE_SECRET_VALUE_LP\"><textarea>CAPTURE_SECRET_TEXTAREA_LP</textarea><span id=\"lp-hidden-ready\" hidden>hidden readiness</span>';document.querySelector('#catalogue').append(box);return true})()"), true);
    report.hiddenAdversariesInstalled = true; return { installed: true };
  });
  for (const [kind, options] of [
    ["snapshot", { maxChars: 8000, maxElements: 20, prioritize: true, prefix: "lp-audit-a-" }],
    ["extract", { scope: "#catalogue", fields: [{ name: "titles", selector: "h3", source: "text", multiple: true }], metadata: true, maxChars: 8000 }],
    ["status", {}], ["ready", { state: "complete", selector: "#unique" }],
  ]) await check("fixed canonical " + kind + " correctness", async () => {
    const expression = fixedObservationExpression(kind, options);
    const value = await evaluate(page, kind === "snapshot" ? "(" + expression + ").snapshot" : expression);
    const serialized = JSON.stringify(value), privateCanaryDetected = serialized.includes("CAPTURE_SECRET_");
    report.observations[kind] = { correct: false, bytes: Buffer.byteLength(serialized), privateCanaryDetected };
    if (kind === "snapshot") Object.assign(report.observations[kind], {
      textChars: value.text?.length, title: value.title,
      safePublicPrefix: privateCanaryDetected ? undefined : value.text?.slice(0, 160),
      controlNames: privateCanaryDetected ? undefined : value.elements?.slice(0, 10).map(el => el.name),
    });
    assert.equal(report.hiddenAdversariesInstalled, true);
    assert.equal(privateCanaryDetected, false);
    if (kind === "snapshot") {
      for (const hidden of ["HIDDEN_ATTRIBUTE_LP", "HIDDEN_DISPLAY_LP", "HIDDEN_INHERITED_LP"])
        assert.ok(!serialized.includes(hidden), "Snapshot included hidden public text");
      assert.deepEqual(value.elements.slice(0, 10).map(element => element.name), ["Confirm order", "Duplicate action", "Duplicate action", "Disabled action", "Covered action", "Remove blocking overlay", "Moving action", "Start moving target", "Stop moving target", "Details"]);
      assert.ok(value.elements.some(el => el.name === "Confirm order"));
      assert.equal(value.elements.length, 20); assert.equal(value.truncated, true);
      assert.ok(value.text.length <= 8000 && value.elements.every(el => el.ref.startsWith("lp-audit-a-")));
      assert.equal(new Set(value.elements.map(el => el.ref)).size, 20);
    } else if (kind === "extract") assert.ok(JSON.stringify(value.fields[0].values) === JSON.stringify(["Green tea", "Black tea"]), "Extraction included hidden/private or unexpected records");
    else if (kind === "status") assert.ok(value.viewport.width > 0 && value.documentState === "complete");
    else assert.ok(value.ready && value.visible && value.matches === 1);
    report.observations[kind] = { correct: true, bytes: Buffer.byteLength(JSON.stringify(value)) };
    return report.observations[kind];
  });
  await check("scoped canonical snapshot with fresh host references", async () => {
    const value = await evaluate(page, "(" + fixedObservationExpression("snapshot", {
      scope: "#catalogue", prefix: "lp-audit-b-", maxElements: 20, maxChars: 8000, prioritize: true,
    }) + ").snapshot");
    const serialized = JSON.stringify(value);
    assert.ok(!serialized.includes("CAPTURE_SECRET_"));
    for (const hidden of ["HIDDEN_ATTRIBUTE_LP", "HIDDEN_DISPLAY_LP", "HIDDEN_INHERITED_LP"])
      assert.ok(!serialized.includes(hidden), "Scoped snapshot included hidden public text");
    assert.ok(!value.elements.some(element => element.name === "Confirm order"), "Snapshot escaped its catalogue scope");
    for (const name of ["Available products", "Green tea", "Black tea"])
      assert.ok(value.elements.some(element => element.name === name), name);
    assert.equal(value.elements.filter(element => element.role === "link" && element.name === "Details").length, 2);
    assert.ok(value.elements.every(element => element.ref.startsWith("lp-audit-b-")));
    assert.equal(new Set(value.elements.map(element => element.ref)).size, value.elements.length);
    return { elements: value.elements.length, textChars: value.text.length, privateCanaryDetected: false };
  });
  await check("hidden selector readiness refuses", async () => {
    const value = await evaluate(page, fixedObservationExpression("ready", { state: "complete", selector: "#lp-hidden-ready" }));
    assert.equal(value.ready, false); assert.equal(value.visible, false); return { refused: true };
  });
  const additionalHidden = await check("install opacity/collapse readiness adversaries", async () => {
    assert.equal(await evaluate(page, "(()=>{const box=document.createElement('div');box.innerHTML='<div style=\\\"opacity:0\\\"><h3>HIDDEN_OPACITY_LP</h3><span id=\\\"lp-opacity-ready\\\">hidden</span></div><div style=\\\"visibility:collapse\\\"><h3>HIDDEN_COLLAPSE_LP</h3><span id=\\\"lp-collapse-ready\\\">hidden</span></div>';document.querySelector('#catalogue').append(box);return true})()"),true);
    return {installed:true};
  });
  report.readerDiagnostics = await runLightpandaReaderDiagnostics({
    check, adversariesInstalled:()=>additionalHidden&&report.hiddenAdversariesInstalled===true,
    read: async (kind,options={}) => {
      const expression=fixedObservationExpression(kind,options);
      return evaluate(page,kind==="snapshot"?"("+expression+").snapshot":expression);
    },
  });
  report.domSupport = await evaluate(page, "({rects:typeof document.body.getClientRects,style:typeof getComputedStyle,webmcp:typeof document.modelContext})");
  await check("history back/forward", async () => {
    const next = new URL("next", fixture.url).href;
    await page.goto(next, { waitUntil: "domcontentloaded", timeout: 5000 });
    await page.goBack({ timeout: 3000 }); assert.equal(page.url(), new URL(fixture.url).href);
    await page.goForward({ timeout: 3000 }); assert.equal(page.url(), next);
    report.verifiedMethods.push("tab.back", "tab.forward"); return { history: true };
  });
  await check("reload", async () => { await page.goto(fixture.url, { waitUntil: "domcontentloaded", timeout: 5000 }); await page.reload({ timeout: 3000 }); assert.equal(await page.title(), "Kelpie capture acceptance"); report.verifiedMethods.push("tab.reload"); });
  await a.close();
  const automation = await browser.newContext({ serviceWorkers: "block", acceptDownloads: false }); contexts.push(automation);
  const borrowed = await automation.newPage();
  await check("close then new context storage isolation", async () => {
    assert.equal(report.previousStateSet, true);
    await borrowed.goto(fixture.url, { waitUntil: "domcontentloaded", timeout: 5000 });
    const value = await evaluate(borrowed, "({cookie:document.cookie,storage:localStorage.getItem('lp_owned')})");
    assert.ok(!value.cookie.includes("lp_owned=one")); assert.equal(value.storage, null); return { sequentialIsolation: true };
  });
  const methods = [...new Set(["tabs.list", "tabs.close", ...(multiplePages ? ["tabs.new"] : []), ...report.verifiedMethods])];
  const make = async isolation => {
    const session = await allocateManagedBrowserSession({ browser, backend: "lightpanda", owner: "fixture-operator", authorize() {},
      options: { isolation, ttlMs: 60000 }, sharedContext: automation, verifiedLightpandaMethods: methods,
      network: { boundary: "operator-enforced", allowNavigation: url => url.origin === origin } });
    sessions.push(session); return session;
  };
  await check("managed shared isolation refuses before allocation", async () => {
    await assert.rejects(()=>make("shared"),error=>error?.code==="ISOLATION_UNAVAILABLE");
    return {shared:"ISOLATION_UNAVAILABLE"};
  });
  await automation.close();
  await check("single managed isolated session with explicit one-tab ceiling", async () => {
    const single = await allocateManagedBrowserSession({ browser, backend: "lightpanda", owner: "fixture-single-operator",
      authorize() {}, options: { isolation: "isolated", ttlMs: 60000 }, maxTabs: 1,
      verifiedLightpandaMethods: methods.filter(method => method !== "tabs.new"),
      network: { boundary: "operator-enforced", allowNavigation: url => url.origin === origin } });
    sessions.push(single);
    const tabId = single.describe().ownedTabIds[0];
    const call = (method, params = {}, id = tabId) => single.transport.call({ version: 1, method, params, tabId: id });
    assert.equal((await call("tab.goto", { url: fixture.url })).ok, true);
    assert.equal((await call("tab.title")).value, "Kelpie capture acceptance");
    assert.equal((await call("tabs.list")).value.length, 1);
    for (const method of ["tabs.new", "tab.screenshot", "tab.snapshot", "tab.extract", "page.scroll"]) {
      const params = method === "tab.extract" ? { fields: [{ name: "title", selector: "h1", source: "text" }] } :
        method === "page.scroll" ? { deltaY: 10 } : {};
      const refused = await call(method, params); assert.equal(refused.ok, false); assert.equal(refused.error.code, "UNSUPPORTED");
    }
    const foreign = await call("tab.title", {}, "foreign-tab"); assert.equal(foreign.ok, false); assert.equal(foreign.error.code, "TAB_NOT_FOUND");
    await single.close();
    assert.equal((await call("tab.title")).ok, false);
    const after = await browser.newContext(); contexts.push(after);
    const afterPage = await after.newPage(); await afterPage.goto(fixture.url, { waitUntil: "domcontentloaded", timeout: 5000 });
    assert.equal(await afterPage.title(), "Kelpie capture acceptance"); await after.close();
    return { oneOwnedTab: true, unsupportedMethodsRefused: true, foreignRefused: true, freshContextAfterClose: true };
  });
  report.resources = { memoryPeak: (await readFile(cgroup + "/memory.peak", "utf8")).trim(), cpu: (await readFile(cgroup + "/cpu.stat", "utf8")).trim() };
} catch (error) {
  report.fatal = String(error.message).slice(0, 1000);
} finally {
  if (client) await bounded(client.close(), 2000).catch(() => {});
  if (transport?.pid && await alive(transport.pid)) { try { process.kill(transport.pid, "SIGTERM"); } catch {} }
  for (const session of sessions) await bounded(session.close(), 1500).catch(error => { report.cleanupError = String(error.message).slice(0, 100); });
  for (const context of contexts) await bounded(context.close(), 1500).catch(() => {});
  if (browser) await bounded(browser.close(), 1500).catch(() => {});
  if (lp) { await stop(lp); report.lpExited = lp.exitCode !== null || lp.signalCode !== null; }
  if (fixture) await fixture.close();
  report.wallMs = performance.now() - start; report.lpLogs = stderr;
  await writeFile(join(output, "report.json"), JSON.stringify(report, null, 2), { mode: 0o600 });
  console.log(JSON.stringify(report, null, 2));
  if (report.fatal || report.cleanupError || !report.readerDiagnostics || Object.values(report.readerDiagnostics).some(value => !value)) process.exitCode = 1;
}
