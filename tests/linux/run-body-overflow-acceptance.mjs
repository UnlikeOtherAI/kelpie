#!/usr/bin/env node
// Real native CDP dispatch against the propagated and contained BODY cases.
import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {createServer} from "node:http";
import {mkdtemp,readFile,writeFile} from "node:fs/promises";
import {join,resolve} from "node:path";
import {startBrowser,stopBrowser,waitForReadiness} from "../windows/lib/process.mjs";
import {control} from "../windows/lib/http.mjs";

const [binaryArg,outputArg]=process.argv.slice(2);
assert.ok(binaryArg&&outputArg);assert.match(process.env.KELPIE_CAPTURE_SOURCE??"",/^[a-f0-9]{40}$/);
const binary=resolve(binaryArg),output=resolve(outputArg),profile=await mkdtemp("/tmp/kelpie-body-test-");
const readyPath=join(profile,"ready.json"),cases={
  propagated:"html{overflow:visible}body{margin:0;height:0;overflow:hidden}",
  contained:"html{overflow:visible}body{margin:0;position:relative;height:0;overflow:hidden;contain:layout}",
  root:"html{height:0;overflow:hidden}body{margin:0;overflow:visible}",
};
const fixture=createServer((req,res)=>{const style=cases[req.url?.slice(1)];if(!style){res.writeHead(404).end();return;}
  res.setHeader("content-type","text/html");res.end('<style>'+style+'button{position:absolute;left:40px;top:230px;width:30px;height:30px}</style><button id="first">First</button><script>window.clickFacts=[];document.querySelector("#first").onclick=e=>clickFacts.push({trusted:e.isTrusted})</script>');});
await new Promise((ok,bad)=>{fixture.once("error",bad);fixture.listen(0,"127.0.0.1",ok);});
const app=startBrowser(binary,["--headless","--port","0","--profile-dir",profile,"--readiness-file",readyPath,"--width","800","--height","600","--url","about:blank"]);
const report={source:process.env.KELPIE_CAPTURE_SOURCE,binarySHA256:createHash("sha256").update(await readFile(binary)).digest("hex"),checks:[]};
let ready,failure;
try {
  ready=await waitForReadiness(readyPath,30000);
  const api=async(method,body={})=>{const r=await fetch('http://127.0.0.1:'+ready.port+'/v1/'+method,{method:"POST",headers:{authorization:'Bearer '+ready.token,"content-type":"application/json"},body:JSON.stringify(body),signal:AbortSignal.timeout(20000)});return r.json();};
  const tabId=(await api("get-tabs")).tabs.find(item=>item.active).id;
  for(const [name,accepted] of [["propagated",true],["contained",false],["root",true]]) {
    const url='http://127.0.0.1:'+fixture.address().port+'/'+name;
    assert.equal((await api("navigate",{tabId,url})).success,true);
    let loaded=false;for(let i=0;i<100&&!loaded;i++){const r=await api("evaluate",{tabId,expression:"document.readyState==='complete' && !!document.querySelector('#first')"});loaded=r.success&&r.result===true;if(!loaded)await new Promise(ok=>setTimeout(ok,50));}
    assert.ok(loaded,"fixture not ready");
    const hit=await api("evaluate",{tabId,expression:"document.elementFromPoint(55,245)?.id ?? null"});
    const result=await api("play-script",{version:1,tabId,actions:[{action:"click",target:{selector:"#first"}}]});
    const facts=await api("evaluate",{tabId,expression:"window.clickFacts"});
    assert.equal(hit.result==="first",accepted);assert.equal(result.success,accepted);
    assert.equal(facts.result.length,accepted?1:0);if(accepted)assert.equal(facts.result[0].trusted,true);
    report.checks.push({name,passed:true,hit:hit.result,success:result.success,events:facts.result.length,trusted:accepted?facts.result[0].trusted:null});
  }
} catch(error){failure=error;report.failure=error.message;}
finally {
  await new Promise(ok=>fixture.close(ok));
  try{await stopBrowser(app,{gracefulClose:ready?()=>control(ready,"close-browser"):undefined,timeoutMs:15000});}catch(error){failure??=error;}
  report.exitCode=app.child.exitCode;report.signal=app.child.signalCode;
  await writeFile(output,JSON.stringify(report,null,2)+"\n",{flag:"wx"});
}
if(failure)throw failure;
