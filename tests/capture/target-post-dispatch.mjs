import assert from "node:assert/strict";
import {createRequire} from "node:module";
import {writeFile} from "node:fs/promises";
import {resolveScriptTarget} from "../../packages/shared/src/script-target.ts";

const require=createRequire(new URL("../../packages/cli/package.json",import.meta.url));
const {chromium}=require("playwright-core");
const output=process.argv[2];assert.ok(output,"Provide a fresh ignored report path");
const browser=await chromium.launch({headless:true,chromiumSandbox:true,
  ...(process.env.KELPIE_CHROMIUM_EXECUTABLE?{executablePath:process.env.KELPIE_CHROMIUM_EXECUTABLE}:{})});
const report={browser:browser.version(),cases:[]},source=resolveScriptTarget.toString();
const timer=setTimeout(()=>{void browser.close().finally(()=>process.exit(124));},25000);
try{
 const page=await browser.newPage();
 await page.route("https://post-dispatch.test/**",route=>route.fulfill({contentType:"text/html",
  body:'<!doctype html><button id="target">Submit</button><input id="edit" type="text" autocomplete="off">'}));
 for(const action of ["click","input"])for(const mutation of ["url","replace"])for(const capture of [false,true]){
  await page.goto("https://post-dispatch.test/start");
  await page.evaluate(({action,mutation})=>{
   window.eventCount=0;
   const el=document.getElementById(action==="click"?"target":"edit");
   el.addEventListener(action,()=>{
    window.eventCount++;
    if(action==="input")el.autocomplete="current-password";
    if(mutation==="url")history.replaceState({},"","/after");
    else el.replaceWith(el.cloneNode(true));
   });
  },{action,mutation});
  const selector=action==="click"?"#target":"#edit",call=args=>page.evaluate("("+source+")(..."+JSON.stringify(args)+")");
  const first=await call([{selector},"post-dispatch"]);assert.equal(first.ok,true);
  const args=action==="click"?[{selector},"post-dispatch",first.token,true,undefined,false,{refuseSensitive:capture}]:
    [{selector},"post-dispatch",first.token,false,{action:"fill",text:"SYNTHETIC_POST_INPUT"},false,{refuseSensitive:capture}];
  const result=await call(args);
  assert.equal(result.ok,action==="click" || !capture);
  if(action==="input" && capture)assert.equal(result.error,"SENSITIVE_CAPTURE_REFUSED");
  assert.equal(result.mayHaveCompleted,true);assert.equal(result.sensitivityKnown,true);
  assert.equal(result.sensitive,action==="input");
  assert.equal(await page.evaluate(()=>window.eventCount),1);
  report.cases.push({action,mutation,capture,ok:result.ok,error:result.error,
    mayHaveCompleted:result.mayHaveCompleted,sensitivityKnown:result.sensitivityKnown,sensitive:result.sensitive});
 }
 for(const change of ["autocomplete","type"])for(const capture of [false,true]){
  await page.goto("https://post-dispatch.test/start");
  await page.evaluate(change=>{const el=document.getElementById("edit");el.addEventListener("input",()=>{
   if(change==="type")el.type="password";else el.autocomplete="current-password";
  })},change);
  const call=args=>page.evaluate("("+source+")(..."+JSON.stringify(args)+")");
  const first=await call([{selector:"#edit"},"post-sensitive"]);assert.equal(first.ok,true);
  const result=await call([{selector:"#edit"},"post-sensitive",first.token,false,
    {action:"fill",text:"SYNTHETIC_POST_INPUT"},false,{refuseSensitive:capture}]);
  assert.equal(result.sensitive,true);assert.equal(result.sensitivityKnown,true);
  assert.equal(result.ok,!capture);
  if(capture){assert.equal(result.error,"SENSITIVE_CAPTURE_REFUSED");assert.equal(result.mayHaveCompleted,true);}
  report.cases.push({action:"input",change,capture,ok:result.ok,error:result.error??null,
    sensitivityKnown:result.sensitivityKnown,sensitive:result.sensitive});
 }
}finally{
 clearTimeout(timer);await writeFile(output,JSON.stringify(report,null,2),{flag:"wx"});await browser.close();
}
