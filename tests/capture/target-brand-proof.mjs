import assert from "node:assert/strict";
import {createRequire} from "node:module";
import {writeFile} from "node:fs/promises";
import {resolveScriptTarget} from "../../packages/shared/src/script-target.ts";
const require=createRequire(new URL("../../packages/cli/package.json",import.meta.url));
const {chromium}=require("playwright-core");
const output=process.argv[2];assert.ok(output);
const browser=await chromium.launch({headless:true,chromiumSandbox:true});
const report={browser:browser.version(),cases:[]},source=resolveScriptTarget.toString();
const timer=setTimeout(()=>{void browser.close().finally(()=>process.exit(124));},20000);
try {
 const page=await browser.newPage(),cdp=await page.context().newCDPSession(page);
 await page.setContent('<style>body{margin:0} a,button,label,input{display:block;width:200px;height:40px;margin:8px} #child{display:block;width:100%;height:100%}</style><a id="link" href="#next">Next</a><button id="button">Go</button><label id="label" for="input">Label</label><input id="input" type="text"><button id="parent"><span id="child">Child</span></button>');
 const frame=(await cdp.send("Page.getFrameTree")).frameTree.frame.id;
 const {executionContextId}=await cdp.send("Page.createIsolatedWorld",{frameId:frame,worldName:"kelpie.brand-test"});
 const call=async args=>{
  const result=await cdp.send("Runtime.evaluate",{expression:"("+source+")(..."+JSON.stringify(args)+")",contextId:executionContextId,returnByValue:true});
  assert.ok(!result.exceptionDetails);return result.result.value;
 };
 for(const [selector,expected] of [["#link","non-input"],["#button","non-input"],["#label","unknown"],["#input","input"],["#parent","unknown"]]){
  const target={selector},first=await call([target,"brand-test"]);assert.equal(first.ok,true,selector);
  const result=await call([target,"brand-test",first.token,false,null,false,null,false,true]);
  assert.equal(result.ok,true,selector);assert.equal(result.sensitivityClass,expected,selector);
  assert.equal(result.sensitivityKnown,true);report.cases.push({selector,classification:result.sensitivityClass});
 }
 const link=await call([{selector:"#link"},"brand-link"]);assert.equal(link.ok,true);
 await cdp.send("Runtime.evaluate",{expression:"Object.setPrototypeOf(document.querySelector(\"#link\"), HTMLElement.prototype)",contextId:executionContextId,returnByValue:true});
 const linkProof=await call([{selector:"#link"},"brand-link",link.token,false,null,false,null,false,true]);
 assert.equal(linkProof.sensitivityClass,"non-input");report.cases.push({name:"anchor-prototype-change",classification:linkProof.sensitivityClass});
 await page.evaluate(()=>{const el=document.querySelector("#input");Object.setPrototypeOf(el,HTMLElement.prototype);el.setAttribute("type","password");});
 const first=await call([{selector:"#input"},"brand-input"]);assert.equal(first.ok,true);
 const result=await call([{selector:"#input"},"brand-input",first.token,false,null,false,null,false,true]);
 assert.equal(result.sensitivityClass,"input");assert.equal(result.sensitive,true);assert.equal(result.sensitivityKnown,true);
 report.cases.push({name:"main-world-input-prototype-change",classification:result.sensitivityClass,sensitive:result.sensitive});
 await cdp.send("Runtime.evaluate",{expression:"Object.setPrototypeOf(document.querySelector(\"#input\"), HTMLElement.prototype)",contextId:executionContextId,returnByValue:true});
 const changed=await call([{selector:"#input"},"brand-input",first.token,false,null,false,null,false,true]);
 assert.equal(changed.sensitivityClass,"input");assert.equal(changed.sensitive,true);
 report.cases.push({name:"isolated-world-input-prototype-change",classification:changed.sensitivityClass,sensitive:changed.sensitive});
 await page.evaluate(()=>document.querySelector("#input").setAttribute("type","text"));
 const ordinary=await call([{selector:"#input"},"brand-change"]);assert.equal(ordinary.ok,true);
 await page.evaluate(()=>document.querySelector("#input").setAttribute("type","password"));
 const changedType=await call([{selector:"#input"},"brand-change",ordinary.token,false,null,false,{refuseSensitive:true},false,true]);
 assert.equal(changedType.ok,false);assert.equal(changedType.sensitive,true);
 report.cases.push({name:"input-changed-to-password",refused:true,sensitive:true});
 const old=await call([{selector:"#button"},"brand-replace"]);assert.equal(old.ok,true);
 await page.evaluate(()=>{const el=document.querySelector("#button");el.replaceWith(el.cloneNode(true));});
 const replacement=await call([{selector:"#button"},"brand-replace",old.token,false,null,false,null,false,true]);
 assert.equal(replacement.ok,false);assert.equal(replacement.error,"STALE_TARGET");
 report.cases.push({name:"replacement-before-proof",refused:true});
} finally {clearTimeout(timer);await writeFile(output,JSON.stringify(report,null,2),{flag:"wx"});await browser.close();}
