import assert from "node:assert/strict";
import { writeFile } from "node:fs/promises";
import { join } from "node:path";
import { startCaptureFixture } from "../capture/fixture-server.mjs";

/** Facts for cross-engine failures; canonical acceptance assertions remain unchanged. */
export async function runAdversaryDiagnostics(readiness, output, signal) {
  const fixture = await startCaptureFixture(), facts = [];
  const api = async (method, body = {}) => {
    const response = await fetch("http://127.0.0.1:" + readiness.port + "/v1/" + method, {
      method: "POST", headers: { authorization: "Bearer " + readiness.token, "content-type": "application/json" },
      body: JSON.stringify(body), signal: AbortSignal.any([signal, AbortSignal.timeout(40000)]),
    });
    const value = await response.json();
    if (response.status === 400) {
      assert.equal(value.success, false);
      assert.ok(typeof value.error?.code === "string" && value.error.code.length);
    } else assert.equal(response.status, 200);
    return value;
  };
  const tabId = (await api("get-tabs")).tabs.find(tab => tab.active)?.id;
  const script = actions => ({ version: 1, tabId, actions });
  const evaluate = async expression => (await api("evaluate", { tabId, expression })).result;
  const navigate = async () => {
    assert.equal((await api("navigate", { tabId, url: fixture.url })).success, true);
    assert.equal((await api("play-script", script([{ action: "wait-ready", state: "complete" }]))).success, true);
  };
  const summarize = value => ({ success: value.success, code: value.error?.code, mayHaveCompleted: value.mayHaveCompleted,
    actionsExecuted: value.actionsExecuted, totalDurationMs: value.totalDurationMs,
    artifacts: value.artifacts?.map(({ mimeType, byteLength, frameCount, partial }) => ({ mimeType, byteLength, frameCount, partial })) });
  const check = async (name, run) => {
    try { facts.push({ name, ...await run() }); }
    catch (error) { facts.push({ name, diagnosticError: error.message }); }
  };
  try {
    await check("readonly focus facts", async () => {
      await navigate();
      const before = await evaluate("(()=>{const e=document.querySelector('#focus-readonly');e.scrollIntoView({block:'center'});window.__diag={inputs:0,focus:[]};e.addEventListener('input',()=>__diag.inputs++);e.addEventListener('focus',()=>__diag.focus.push({time:performance.now(),readonly:e.readOnly}));return{readonly:e.readOnly,focused:document.activeElement===e,empty:e.value===''};})()");
      const result = await api("play-script", script([{ action: "fill", target: { selector: "#focus-readonly" }, text: "MUST_NOT_ENTER" }]));
      const after = await evaluate("(()=>{const e=document.querySelector('#focus-readonly');return{readonly:e.readOnly,focused:document.activeElement===e,empty:e.value==='',...window.__diag};})()");

      return { result: summarize(result), before, after, safety: { refused: !result.success, unchanged: after.empty, noInput: after.inputs === 0 } };
    });
    await check("moving target and recovery facts", async () => {
      await navigate(); const start = fixture.events.length;
      const click = name => ({ action: "click", target: { role: "button", name, exact: true } });
      const result = await api("play-script", { ...script([click("Start moving target"), click("Moving action")]),
        pointer: { enabled: true, curve: "s", durationMs: 300, easing: "ease-in-out" } });
      const recovery = await api("play-script", script([click("Stop moving target")]));
      const events = fixture.events.slice(start).filter(event => event.type === "click");
      const scene = await evaluate("(()=>{const e=document.querySelector('#stop-moving'),r=e.getBoundingClientRect();return{animations:document.getAnimations().length,stopHit:document.elementFromPoint(r.x+r.width/2,r.y+r.height/2)?.id};})()");

      return { result: summarize(result), recovery: summarize(recovery), events, scene, noMovingClick: !events.some(event => event.target === "moving") };
    });
    await check("retained byte budget facts", async () => {
      await navigate();
      const capture = { formats: ["gif"], fps: 15, maxWidth: 640, maxDurationMs: 10000, maxBytes: 150000 };
      const result = await api("play-script", { ...script([{ action: "wait", ms: 2000 }]), capture });
      assert.ok((result.artifacts ?? []).reduce((sum, item) => sum + item.byteLength, 0) <= capture.maxBytes);
      return { result: summarize(result), requestedBytes: capture.maxBytes };
    });
    await check("replacement timing facts", async () => {
      await navigate();
      await evaluate("(()=>{const e=document.querySelector('#next');e.scrollIntoView({block:'center'});const scheduled=performance.now(),documentId=window.captureFixture.documentId;setTimeout(()=>{e.replaceWith(e.cloneNode(true));navigator.sendBeacon('/events',new Blob([JSON.stringify({documentId,type:'replacement-diagnostic',scheduled,time:performance.now(),oldConnected:e.isConnected})],{type:'application/json'}));},300);return true;})()");
      const start = fixture.events.length;
      const result = await api("play-script", { ...script([{ action: "click", target: { selector: "#next" } }]),
        capture: { formats: ["gif", "video"], fps: 1, maxWidth: 640, maxBytes: 8388608, maxDurationMs: 20000 } });
      const events = fixture.events.slice(start).filter(event => event.type === "click" || event.type === "replacement-diagnostic");
      return { result: summarize(result), events, currentURL: (await api("get-current-url", { tabId })).url };
    });
    const report = { source: process.env.KELPIE_CAPTURE_SOURCE, testSource: process.env.KELPIE_TEST_REVISION, facts };
    await writeFile(join(output, "adversary-diagnostics.json"), JSON.stringify(report, null, 2));
    return report;
  } finally { await fixture.close(); }
}
