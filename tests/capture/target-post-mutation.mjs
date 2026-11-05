import assert from "node:assert/strict";
import {createRequire} from "node:module";
import {writeFile} from "node:fs/promises";
import {resolveScriptTarget} from "../../packages/shared/src/script-target.ts";

const require=createRequire(new URL("../../packages/cli/package.json",import.meta.url));
const {chromium}=require("playwright-core");
const output=process.argv[2];assert.ok(output);
const browser=await chromium.launch({headless:true,chromiumSandbox:true,
  ...(process.env.KELPIE_CHROMIUM_EXECUTABLE?{executablePath:process.env.KELPIE_CHROMIUM_EXECUTABLE}:{})});
const report={browser:browser.version(),cases:[]},source=resolveScriptTarget.toString();
const timer=setTimeout(()=>{void browser.close().finally(()=>process.exit(124));},25000);
try {
 const page=await browser.newPage();
 await page.route("https://post-mutation.test/**",route=>route.fulfill({contentType:"text/html",
  body:'<!doctype html><button id="target">Submit</button><input id="edit" type="text" autocomplete="off">'}));
 for(const action of ["click","input"])for(const mutation of ["none","url","replace","geometry","sensitive","realm"]) {
  await page.goto("https://post-mutation.test/start");
  const selector=action==="click"?"#target":"#edit";
  await page.evaluate(({selector,action,mutation})=>{
   const el=document.querySelector(selector); window.eventCount=0; window.trusted=false;
   el.addEventListener(action,event=>{
    window.eventCount++; window.trusted=event.isTrusted;
    if(mutation==="url")history.replaceState({},"","/after");
    if(mutation==="replace")el.replaceWith(el.cloneNode(true));
    if(mutation==="geometry")el.style.display="none";
    if(mutation==="sensitive" && el instanceof HTMLInputElement)el.autocomplete="current-password";
   });
  },{selector,action,mutation});
  const call=args=>page.evaluate("("+source+")(..."+JSON.stringify(args)+")");
  const first=await call([{selector},"post-mutation"]);assert.equal(first.ok,true);
  if(action==="click") await page.click(selector);
  else await page.fill(selector,"SYNTHETIC_POST_INPUT");
  assert.deepEqual(await page.evaluate(()=>[window.eventCount,window.trusted]),[1,true]);
  if(mutation==="realm")await page.goto("https://post-mutation.test/new");
  const result=await call([{selector},"post-mutation",first.token,false,null,false,{refuseSensitive:true},true]);
  assert.equal(result.ok,true);
  assert.equal(result.sensitivityKnown,mutation!=="realm");
  assert.equal(result.sensitive,action==="input" && mutation==="sensitive");
  if(mutation!=="realm"){assert.equal(result.token,first.token);assert.equal(result.documentId,first.documentId);}
  report.cases.push({action,mutation,ok:result.ok,sensitive:result.sensitive,sensitivityKnown:result.sensitivityKnown});
 }
}finally{
 clearTimeout(timer);await writeFile(output,JSON.stringify(report,null,2),{flag:"wx"});await browser.close();
}
