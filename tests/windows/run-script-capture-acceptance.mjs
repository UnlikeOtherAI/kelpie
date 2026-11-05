import assert from "node:assert/strict";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { createHash } from "node:crypto";
import { resolve } from "node:path";
import { startCaptureFixture } from "../capture/fixture-server.mjs";
import { scriptArtifactSchema, scriptArtifactChunkSchema, scriptStatusV1Schema } from "../../packages/shared/dist/index.js";

const [readinessPath, outputPath] = process.argv.slice(2);
if (!readinessPath || !outputPath) throw new Error("Provide private readiness path and fresh evidence directory");
const readiness = JSON.parse(await readFile(readinessPath, "utf8"));
assert.equal(readiness.controlMode, "loopback");
assert.equal(readiness.port,Number(process.env.KELPIE_CAPTURE_PORT??28420));
const output = resolve(outputPath);
await mkdir(output, { recursive: false });
const fixture = await startCaptureFixture();
const checks = [];
const artifacts = [];
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function request(method, body = {}, token = readiness.token) {
  const response = await fetch("http://127.0.0.1:" + readiness.port + "/v1/" + method, {
    method: "POST", headers: { authorization: "Bearer " + token, "content-type": "application/json" },
    body: JSON.stringify(body), signal: AbortSignal.timeout(360000),
  });
  return { status: response.status, value: await response.json() };
}
async function api(method, body = {}) {
  const { value } = await request(method, body);
  if(method==="get-script-status" && value.success) scriptStatusV1Schema.parse(value);
  return value;
}
async function mcp(method, body = {}, generic = true) {
  const response = await fetch("http://127.0.0.1:" + readiness.port + "/mcp", {
    method: "POST", headers: { authorization: "Bearer " + readiness.token, "content-type": "application/json",
      accept: "application/json, text/event-stream" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call",
      params: generic ? { name: "kelpie_extension", arguments: { name: method, arguments: body } } : {name:method,arguments:body} }),
    signal: AbortSignal.timeout(360000),
  });
  const envelope = await response.json();
  assert.equal(envelope.error, undefined);
  const wrapped = JSON.parse(envelope.result.content[0].text);
  const value=wrapped.ok ? wrapped.value : { success: false, error: wrapped.error };
  if(method==="kelpie_get_script_status" && value.success) scriptStatusV1Schema.parse(value);
  return value;
}
async function check(name, run) {
  if(process.env.KELPIE_CAPTURE_CASE_FILTER && !name.includes(process.env.KELPIE_CAPTURE_CASE_FILTER)) return;
  try { const detail = await run(); checks.push({ name, passed: true, detail }); }
  catch (error) { checks.push({ name, passed: false, error: error.message }); }
}
async function download(run) {
  assert.equal(typeof run.runId, "string");
  for (const raw of run.artifacts ?? []) {
    const manifest = scriptArtifactSchema.parse(raw);
    const chunks = []; let offset = 0;
    while (offset < manifest.byteLength) {
      const chunk = scriptArtifactChunkSchema.parse(await api("get-script-artifact", {
        runId: run.runId, artifactId: manifest.id, offset, length: 262144,
      }));
      assert.equal(chunk.runId, run.runId); assert.equal(chunk.artifactId, manifest.id);
      assert.equal(chunk.offset, offset); assert.equal(chunk.sha256, manifest.sha256);
      const bytes = Buffer.from(chunk.data, "base64");
      assert.equal(chunk.nextOffset, offset + bytes.length); assert.ok(bytes.length > 0);
      chunks.push(bytes); offset = chunk.nextOffset;
      assert.equal(chunk.eof, offset === manifest.byteLength);
    }
    const bytes = Buffer.concat(chunks);
    assert.equal(bytes.length, manifest.byteLength);
    assert.equal(createHash("sha256").update(bytes).digest("hex"), manifest.sha256);
    const extension = { "image/png": "png", "image/gif": "gif", "video/mp4": "mp4" }[manifest.mimeType];
    await writeFile(resolve(output, manifest.id + "." + extension), bytes);
    artifacts.push({ runId: run.runId, ...manifest });
  }
}
let tabId;
const workflow = actions => ({ version: 1, tabId, actions });
const click = name => ({ action: "click", target: { role: "button", name, exact: true } });
async function navigate() {
  const response = await api("navigate", { tabId, url: fixture.url });
  assert.equal(response.success, true, JSON.stringify(response.error));
  await delay(300);
}
try {
  const tabs = await api("get-tabs");
  tabId = (tabs.tabs ?? tabs.result?.tabs).find(tab => tab.active)?.id;
  assert.equal(typeof tabId, "string");
  await check("v1 capability HTTP and MCP", async () => {
    for (const result of [await api("get-script-status"), await mcp("kelpie_get_script_status")]) {
      assert.equal(result.success, true); assert.ok(result.supportedVersions.includes(1));
    }
  });
  await check("continuous GIF MP4 marker PNG semantic trusted center extraction", async () => {
    const result = await api("play-script", {
      ...workflow([{ action: "navigate", url: fixture.url }, { action: "wait-ready", state: "complete" },
        { action: "commentary", text: "Native capture", durationMs: 900 }, click("Confirm order"),
        { action: "extract", name: "products", params: { scope: "#catalogue",
          fields: [{ name: "title", selector: "h3", source: "text", multiple: true }], metadata: true, maxChars: 8000 } },
        { action: "output", name: "title", source: "title" }]),
      capture: { formats: ["gif", "video", "screenshots"], fps: 15, maxWidth: 1000, maxDurationMs: 30000, maxBytes: 16777216 },
      pointer: { enabled: true, curve: "s", durationMs: 300, easing: "ease-in-out" },
      tapIndicator: { color: "#F54242", radius: 24, durationMs: 700, wobble: true, fade: true },
    });
    assert.equal(result.success, true, JSON.stringify(result.error));
    assert.equal(result.inputGuarantee, "trusted-coordinate");
    assert.equal(result.outputs.products.fields[0].status, "ok");
    assert.deepEqual(result.outputs.products.fields[0].values, ["Green tea", "Black tea"]);
    for (const mime of ["image/png", "image/gif", "video/mp4"]) assert.ok(result.artifacts.some(a => a.mimeType === mime));
    await download(result);
    const event = fixture.events.find(event => event.type === "click" && event.target === "unique");
    assert.ok(event); assert.equal(event.trusted, true); assert.equal(event.hit, "unique");
    assert.ok(Math.abs(event.x - (event.visible.left + event.visible.right) / 2) <= 1);
    assert.ok(Math.abs(event.y - (event.visible.top + event.visible.bottom) / 2) <= 1);
    return { runId: result.runId, actionsExecuted: result.actionsExecuted, event };
  });
  for (const [name, code] of [["Duplicate action", "AMBIGUOUS_TARGET"], ["Disabled action", "TARGET_NOT_FOUND"],
    ["Covered action", "TARGET_OBSCURED"], ["Hidden action", "TARGET_NOT_FOUND"]]) {
    await check("safe refusal " + name, async () => {
      await navigate(); const result = await api("play-script", workflow([click(name)]));
      assert.equal(result.success, false); assert.equal(result.error.code, code);
      return { code: result.error.code };
    });
  }
  for (const sessionId of ["unknown-session", "foreign-session"]) {
    await check("external session preflight " + sessionId, async () => {
      const before = await api("get-current-url", { tabId });
      const result = await api("play-script", { ...workflow([{ action: "navigate", url: fixture.url + "/next" }]), sessionId });
      assert.equal(result.success, false); assert.equal(result.error.code, "SESSION_UNSUPPORTED");
      assert.deepEqual(await api("get-current-url", { tabId }), before);
      for(const generic of [false,true]) {
        const refusal=await mcp("kelpie_play_script",{...workflow([{action:"navigate",url:fixture.url+"/next"}]),sessionId},generic);
        assert.equal(refusal.success,false);assert.equal(refusal.error.code,"SESSION_UNSUPPORTED");
        assert.deepEqual(await api("get-current-url",{tabId}),before);
      }
    });
  }
  await check("unresolved bindings and sensitive capture preflight", async () => {
    for (const text of [{ input: "missing" }, { secret: "missing" }]) {
      const result = await api("play-script", workflow([{ action: "fill", target: { selector: "#focus-readonly" }, text }]));
      assert.equal(result.success, false); assert.equal(result.error.code, "UNRESOLVED_INPUT");
    }
    const result = await api("play-script", { ...workflow([{ action: "fill", target: { selector: "#focus-readonly" },
      text: "synthetic-sensitive", sensitive: true }]), capture: { formats: ["gif"] } });
    assert.equal(result.success, false); assert.equal(result.error.code, "SENSITIVE_CAPTURE_REFUSED");
  });
  await check("duplicate outputs preflight", async () => {
    const result = await api("play-script", workflow([{ action: "output", name: "x", source: "title" },
      { action: "output", name: "x", source: "url" }]));
    assert.equal(result.success, false); assert.equal(result.error.code, "DUPLICATE_OUTPUT");
  });
  await check("MCP abort during capture and next run recovery", async () => {
    await navigate();
    const pending = api("play-script", { ...workflow([{ action: "wait", ms: 10000 }]),
      capture: { formats: ["gif", "video"], fps: 15, maxWidth: 640, maxBytes: 8388608 } });
    let status;
    for (let attempt = 0; attempt < 50; attempt++) {
      status = await api("get-script-status"); if (status.playing) break; await delay(100);
    }
    assert.equal(status.playing, true);
    await delay(700);
    const aborted = await mcp("kelpie_abort_script", { runId: status.runId });
    assert.equal(aborted.success, true);
    const result = await pending;
    assert.equal(result.success, false); assert.equal(result.aborted, true);
    for(const generic of [false,true]) {
      const terminal=await mcp("kelpie_get_script_status",{runId:result.runId},generic);
      assert.equal(terminal.success,true);assert.equal(terminal.state,"aborted");assert.equal(terminal.runSuccess,false);
      assert.equal(terminal.error,undefined);assert.equal(terminal.outputs,undefined);
    }
    assert.ok(result.artifacts.length > 0); assert.ok(result.artifacts.every(a => a.partial));
    await download(result);
    const recovery = await mcp("kelpie_play_script", workflow([click("Confirm order")]));
    assert.equal(recovery.success, true, JSON.stringify(recovery.error));
    return { abortedRun: result.runId, recoveryRun: recovery.runId };
  });
  const evaluate=async expression=>{
    const r=await api("evaluate",{tabId,expression});assert.equal(r.success,true);return r.result;
  };
  const reveal=async selector=>{
    const top=await evaluate("document.querySelector("+JSON.stringify(selector)+").getBoundingClientRect().top");
    assert.equal((await api("scroll",{tabId,deltaX:0,deltaY:top-150})).success,true);
  };
  await check("fill type trusted key after semantic focus",async()=>{
    await navigate();await reveal("textarea");
    const result=await api("play-script",workflow([
      {action:"fill",target:{label:"Draft message",exact:true},text:"BOUND_INPUT_053"},
      {action:"type",target:{label:"Draft message",exact:true},text:"_APPEND"},
      {action:"press-key",key:"Enter"}]));
    assert.equal(result.success,true,JSON.stringify(result.error));
    assert.equal(await evaluate("document.querySelector('textarea').value"),"BOUND_INPUT_053_APPEND\n");
    const status=await api("get-script-status",{runId:result.runId});
    assert.ok(!JSON.stringify(status).includes("BOUND_INPUT_053"));return {runId:result.runId};
  });
  await check("selector fill type native diagnostic",async()=>{
    await navigate();await reveal("textarea");
    const result=await api("play-script",workflow([
      {action:"fill",target:{selector:"textarea"},text:"BOUND_INPUT_053"},
      {action:"type",target:{selector:"textarea"},text:"_APPEND"},
      {action:"press-key",key:"Enter"}]));
    assert.equal(result.success,true,JSON.stringify(result.error));
    assert.equal(await evaluate("document.querySelector('textarea').value"),"BOUND_INPUT_053_APPEND\n");
    return {runId:result.runId};
  });
  for(const selector of ["#focus-readonly","#focus-navigate"]) {
    await check("focus race refuses input "+selector,async()=>{
      await navigate();await reveal(selector);
      const result=await api("play-script",workflow([{action:"fill",target:{selector},text:"MUST_NOT_ENTER"}]));
      assert.equal(result.success,false);assert.equal(result.mayHaveCompleted,true);
      assert.equal(await evaluate("document.querySelector("+JSON.stringify(selector)+").value"),"");
      await navigate();
      const recovery=await api("play-script",workflow([click("Confirm order")]));
      assert.equal(recovery.success,true);return {code:result.error.code,recoveryRun:recovery.runId};
    });
  }
  await check("sensitive DOM target refuses capture before editing",async()=>{
    await navigate();await reveal("input[type=password]");
    const before=await evaluate("document.querySelector('input[type=password]').value");
    const result=await api("play-script",{...workflow([{action:"fill",target:{label:"Account password",exact:true},text:"MUST_NOT_ENTER"}]),
      capture:{formats:["gif"],maxWidth:640,maxBytes:8388608}});
    assert.equal(result.success,false);assert.equal(result.error.code,"SENSITIVE_CAPTURE_REFUSED");
    assert.equal(await evaluate("document.querySelector('input[type=password]').value"),before);
    await download(result);return {runId:result.runId};
  });
  await check("moving target refuses after pointer presentation",async()=>{
    await navigate();
    const start=fixture.events.length;
    const result=await api("play-script",{...workflow([click("Start moving target"),click("Moving action")]),
      pointer:{enabled:true,curve:"s",durationMs:300,easing:"ease-in-out"}});
    assert.equal(result.success,false);assert.equal(result.mayHaveCompleted,false);
    assert.ok(!fixture.events.slice(start).some(e=>e.type==="click"&&e.target==="moving"));
    assert.equal((await api("play-script",workflow([click("Stop moving target")]))).success,true);
    return {code:result.error.code};
  });
  await check("child replacement releases pressed state and next run recovers",async()=>{
    await navigate();await reveal("#child-replace");
    const start=fixture.events.length;
    const result=await api("play-script",workflow([{action:"click",target:{selector:"#child-replace"}}]));
    assert.equal(result.success,false);assert.equal(result.mayHaveCompleted,true);
    assert.ok(!fixture.events.slice(start).some(e=>e.type==="click"&&e.target==="child-replace"));
    const recovery=await api("play-script",workflow([{action:"click",target:{selector:"#child-replace"}}]));
    assert.equal(recovery.success,true);return {code:result.error.code,recoveryRun:recovery.runId};
  });
  for(const [name,capture,code] of [
    ["duration",{formats:["gif","video"],fps:15,maxWidth:640,maxDurationMs:100,maxBytes:8388608},"CAPTURE_DURATION_EXCEEDED"],
    ["retained bytes",{formats:["gif"],fps:15,maxWidth:640,maxDurationMs:10000,maxBytes:150000},"CAPTURE_BUDGET_EXCEEDED"]]) {
    await check("capture limit "+name+" produces playable partial",async()=>{
      await navigate();
      const result=await api("play-script",{...workflow([{action:"wait",ms:2000}]),capture});
      assert.equal(result.success,false);assert.equal(result.error.code,code);
      assert.ok(result.artifacts.length>0);assert.ok(result.artifacts.every(a=>a.partial));
      assert.ok(result.artifacts.reduce((bytes,a)=>bytes+a.byteLength,0)<=capture.maxBytes);
      await download(result);
      assert.equal((await api("play-script",workflow([{action:"wait",ms:0}]))).success,true);
      return {runId:result.runId,durationMs:result.totalDurationMs};
    });
  }
  for(const formats of [["gif","video","screenshots"],["gif","video"]]) {
  await check("navigation marker evidence "+formats.join(","),async()=>{
    await navigate();await reveal("#next");
    const oldDocument=await evaluate("window.captureFixture.documentId");
    const eventStart=fixture.events.length;
    const result=await api("play-script",{...workflow([{action:"click",target:{role:"link",name:"Next document",exact:true}}]),
      capture:{formats,fps:1,maxWidth:640,maxBytes:8388608,maxDurationMs:20000},
      tapIndicator:{color:"#FF0000",radius:24,durationMs:700,wobble:false,fade:true}});
    assert.equal(result.success,true,JSON.stringify(result.error));await download(result);
    const clickEvent=fixture.events.slice(eventStart).find(e=>e.type==="click");
    assert.equal(clickEvent.documentId,oldDocument);assert.equal(clickEvent.trusted,true);
    assert.equal((await api("get-current-url",{tabId})).url,fixture.url+"/next");
    return {runId:result.runId,oldDocument,event:clickEvent};
  });
  }

  for(const reason of ["duration","abort","replace"]) {
    await check("movie evidence hold "+reason+" refuses input and recovers",async()=>{
      await navigate();await reveal("#next");const before=fixture.events.length;
      if(reason==="replace") await evaluate("setTimeout(()=>{const e=document.querySelector('#next');e.replaceWith(e.cloneNode(true))},300);true");
      const pending=api("play-script",{...workflow([{action:"click",target:{selector:"#next"}}]),
        capture:{formats:["gif","video"],fps:1,maxWidth:640,maxBytes:8388608,maxDurationMs:reason==="duration"?100:20000}});
      if(reason==="abort") {
        for(let attempt=0;attempt<50;attempt++) {if((await api("get-script-status")).playing)break;await delay(20);}
        await delay(300);assert.equal((await mcp("kelpie_abort_script")).success,true);
      }
      const result=await pending;assert.equal(result.success,false);await download(result);
      assert.ok(!fixture.events.slice(before).some(e=>e.type==="click"&&e.target==="next"));
      assert.ok((await api("get-current-url",{tabId})).url!==fixture.url+"/next");
      const recovery=await api("play-script",workflow([{action:"wait",ms:0}]));
      assert.equal(recovery.success,true);return {runId:result.runId,code:result.error?.code,recovery:recovery.runId};
    });
  }
  await check("MCP failed status preserves partial artifacts and recovery",async()=>{
    await navigate();
    const failed=await mcp("kelpie_play_script",{...workflow([click("Covered action")]),
      capture:{formats:["gif","video"],fps:10,maxWidth:640,maxBytes:8388608}},false);
    assert.equal(failed.success,false);
    const latest=await mcp("kelpie_get_script_status",{},true);
    assert.equal(latest.success,true);assert.equal(latest.state,"failed");assert.equal(latest.runSuccess,false);
    assert.equal(latest.error,undefined);assert.equal(latest.outputs,undefined);
    assert.ok(latest.artifacts.length>0);assert.ok(latest.artifacts.every(a=>a.partial));
    const direct=await mcp("kelpie_get_script_status",{runId:latest.runId},false);
    assert.equal(direct.runId,latest.runId);assert.equal(direct.runSuccess,false);
    await download(latest);
    const manifest=latest.artifacts[0];
    const chunk=scriptArtifactChunkSchema.parse(await mcp("kelpie_get_script_artifact",
      {runId:latest.runId,artifactId:manifest.id,length:1024},false));
    assert.equal(chunk.artifactId,manifest.id);
    const recovery=await mcp("kelpie_play_script",workflow([{action:"wait",ms:0}]),false);
    assert.equal(recovery.success,true);return {failedRun:latest.runId,recoveryRun:recovery.runId};
  });



  await check("strict malformed late actions refuse before mutation",async()=>{
    const before=await api("get-current-url",{tabId});
    const base=workflow([{action:"navigate",url:fixture.url+"/next"}]);
    for(const candidate of [
      {...base,version:2},{...base,unknown:true},{...base,capture:{formats:["gif"],fps:31}},
      {...base,capture:{formats:["gif"],maxBytes:1023}},{...base,capture:{formats:["gif"],maxDurationMs:300001}},
      {...base,actions:[...base.actions,{action:"not-an-action"}]},
      {...base,actions:Array.from({length:1001},()=>({action:"wait",ms:0}))},
      {...base,actions:[...base.actions,{action:"click",target:{x:null,y:0}}]},
      {...base,pointer:{enabled:true,durationMs:-1}}]) {
      const result=await api("play-script",candidate);assert.equal(result.success,false);
      assert.deepEqual(await api("get-current-url",{tabId}),before);
    }
    const legacy=await api("play-script",{actions:[{action:"navigate",url:fixture.url+"/next"}]});
    assert.equal(legacy.success,false);assert.deepEqual(await api("get-current-url",{tabId}),before);
    return {legacy:"unsupported before this Windows adapter; remains explicit refusal"};
  });
  await check("ordered assertions readiness scroll and failure stop",async()=>{
    await navigate();const before=fixture.events.length;
    const result=await api("play-script",workflow([
      {action:"wait-ready",state:"complete",selector:"#unique",timeoutMs:1000},
      {action:"assert",target:{role:"button",name:"Confirm order",exact:true},state:"enabled",timeoutMs:1000},
      {action:"scroll",deltaX:0,deltaY:5000},
      {action:"assert",target:{role:"button",name:"Scrolled action",exact:true},state:"visible",timeoutMs:1000},
      click("Scrolled action"),{action:"output",name:"facts",source:"status"}]));
    assert.equal(result.success,true,JSON.stringify(result.error));
    assert.ok(fixture.events.slice(before).some(e=>e.type==="click"&&e.target==="scroll-target"&&e.trusted));
    const old=await api("get-current-url",{tabId});
    const failed=await api("play-script",workflow([
      {action:"assert",target:{selector:".missing"},state:"visible",timeoutMs:50},
      {action:"navigate",url:fixture.url+"/next"}]));
    assert.equal(failed.success,false);assert.deepEqual(await api("get-current-url",{tabId}),old);
    return {runId:result.runId,failedRun:failed.runId};
  });
  await check("security sensitive native output redacts encoded reflections",async()=>{
    await navigate();await reveal("textarea");
    const secret="Aa b+!",encoded="Aa%20b%2b!";
    const result=await api("play-script",workflow([
      {action:"fill",target:{label:"Draft message",exact:true},text:secret,sensitive:true},
      {action:"navigate",url:fixture.url+"/?echo="+encoded},
      {action:"output",name:"echo",source:"url"}]));
    assert.equal(result.success,true);assert.ok(result.outputs.echo.includes("[redacted]"));
    assert.ok(!JSON.stringify(result).includes(secret));assert.ok(!JSON.stringify(result).includes(encoded));
    const status=await api("get-script-status",{runId:result.runId});
    assert.equal(status.outputs,undefined);return {runId:result.runId};
  });
  await check("security inferred sensitive refusal redacts earlier outputs",async()=>{
    await navigate();
    const canary="Synthetic Aa b+! "+crypto.randomUUID();
    const encoded=encodeURIComponent(canary).replace(/%2B/g,"%2b");
    const form=new URLSearchParams({value:canary}).toString().slice(6).replace(/%2B/g,"%2b");
    assert.equal((await api("evaluate",{tabId,expression:"(()=>{document.title="+JSON.stringify(canary+" "+encoded+" "+form)+";document.body.innerHTML='<input id=password-target type=password aria-label=Password>';window.__sensitiveEdits=0;document.querySelector('input').oninput=()=>window.__sensitiveEdits++;return true;})()"})).success,true);
    const result=await api("play-script",{...workflow([
      {action:"output",name:"before",source:"title"},
      {action:"fill",target:{label:"Password",exact:true},text:canary}
    ]),capture:{formats:["screenshots"],maxWidth:640,maxBytes:8388608}});
    const serialized=JSON.stringify(result);
    const leaked=serialized.includes(canary)||serialized.includes(encoded)||serialized.includes(form);
    const untouched=(await api("evaluate",{tabId,expression:"document.querySelector('input').value===''&&window.__sensitiveEdits===0"})).result===true;
    // Persist booleans only: never include the authored canary or raw result.
    const detail={leaked,untouched,refused:result.error?.code==="SENSITIVE_CAPTURE_REFUSED",runId:result.runId,artifactCount:result.artifacts?.length??0};
    checks.push({name:"inferred-sensitive diagnostic",passed:!leaked&&untouched,detail});
    assert.equal(detail.refused,true);assert.equal(untouched,true);assert.equal(leaked,false,"Earlier output retained inferred secret");
    assert.equal(detail.artifactCount,0);assert.ok(result.outputs.before.includes("[redacted]"));
    const status=await api("get-script-status",{runId:result.runId});assert.equal(status.artifacts.length,0);
    assert.equal((await api("play-script",workflow([{action:"wait",ms:0}]))).success,true);
    return detail;
  });
  await check("security artifact identity and range admission",async()=>{
    await navigate();
    const run=await api("play-script",workflow([{action:"screenshot"}]));assert.equal(run.success,true);
    const item=run.artifacts[0];
    for(const override of [{runId:"foreign-run"},{artifactId:"../capture.mp4"},{offset:-1},
      {offset:item.byteLength+1},{length:1048577},{offset:"0"},{length:0}]) {
      const response=await api("get-script-artifact",{runId:run.runId,artifactId:item.id,offset:0,length:1024,...override});
      assert.equal(response.success,false);
    }
    await download(run);return {runId:run.runId};
  });
  await check("security mutation admission stays BUSY while status and abort work",async()=>{
    await navigate();
    const pending=api("play-script",{...workflow([{action:"wait",ms:3000}]),
      capture:{formats:["gif","video"],fps:15,maxWidth:640,maxBytes:8388608}});
    let current;for(let attempt=0;attempt<50;attempt++){current=await api("get-script-status");if(current.playing)break;await delay(20);}
    assert.equal(current.playing,true);
    const navigation=await api("navigate",{tabId,url:fixture.url+"/next"});
    assert.equal(navigation.success,false);assert.equal(navigation.error.code,"BUSY");
    assert.equal((await mcp("kelpie_abort_script",{runId:current.runId},false)).success,true);
    const result=await pending;assert.equal(result.success,false);await download(result);
    assert.equal((await api("play-script",workflow([{action:"wait",ms:0}]))).success,true);
    return {runId:result.runId};
  });
  await check("invalid bearer cannot read cancel or download", async () => {
    for (const method of ["get-script-status", "abort-script", "get-script-artifact"]) {
      const response = await request(method, {}, "invalid-grant");
      assert.equal(response.status, 401);
    }
  });
  await check("explicit PNG with GIF-only capture is retained",async()=>{
    await navigate();
    const result=await api("play-script",{...workflow([{action:"screenshot",name:"explicit"}]),
      capture:{formats:["gif"],maxWidth:640,maxBytes:8388608}});
    assert.equal(result.success,true);
    assert.ok(result.artifacts.some(a=>a.mimeType==="image/png"));
    await download(result);return {runId:result.runId};
  });
  await check("zero pointer duration C curve screenshot only", async () => {
    await navigate();
    const result = await api("play-script", { ...workflow([click("Confirm order"), { action: "screenshot", name: "zero" }]),
      pointer: { enabled: true, curve: "c", durationMs: 0, easing: "ease-in-out" } });
    assert.equal(result.success, true, JSON.stringify(result.error));
    assert.ok(result.artifacts.some(a => a.mimeType === "image/png")); await download(result);
  });
} finally {
  const report={source:process.env.KELPIE_CAPTURE_SOURCE,port:readiness.port,launchId:readiness.launchId,checks,artifacts};
  await writeFile(resolve(output,"report.json"),JSON.stringify(report,null,2));
  try { await fixture.close();report.cleanup="closed"; }
  catch(error) {report.cleanup="failed";checks.push({name:"fixture cleanup",passed:false,error:error.message});}
  await writeFile(resolve(output,"report.json"),JSON.stringify(report,null,2));
}
console.log(JSON.stringify({ passed: checks.filter(c => c.passed).length, failed: checks.filter(c => !c.passed).map(c => c.name), output }));
if (checks.some(check => !check.passed)) process.exitCode = 1;
