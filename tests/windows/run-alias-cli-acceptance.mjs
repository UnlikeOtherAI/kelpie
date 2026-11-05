import assert from "node:assert/strict";
import {readFile,writeFile,mkdir} from "node:fs/promises";
import {resolve,dirname} from "node:path";
import {pathToFileURL} from "node:url";
import {createRequire} from "node:module";
import {execFile} from "node:child_process";
import {promisify} from "node:util";
import {startCaptureFixture} from "../capture/fixture-server.mjs";
const [entry,alias,home,readinessPath,outputPath]=process.argv.slice(2);
if(!outputPath)throw Error("Provide CLI entry, alias, isolated home, private readiness, fresh output");
const output=resolve(outputPath);await mkdir(output,{recursive:false});
const env={...process.env,KELPIE_HOME:home};
const run=promisify(execFile);
const cli=async(args,extra={})=>{
 const result=await run(process.execPath,[entry,"--browser",alias,...args],{env:{...env,...extra},timeout:360000,windowsHide:true,maxBuffer:2097152});
 return JSON.parse(result.stdout);
};
const require=createRequire(pathToFileURL(resolve(entry)));
const {Client}=await import(pathToFileURL(require.resolve("@modelcontextprotocol/sdk/client/index.js")));
const {StdioClientTransport}=await import(pathToFileURL(require.resolve("@modelcontextprotocol/sdk/client/stdio.js")));
const r=JSON.parse(await readFile(readinessPath,"utf8"));
const api=async(method,body={})=>{
 const response=await fetch("http://127.0.0.1:"+r.port+"/v1/"+method,{method:"POST",
 headers:{authorization:"Bearer "+r.token,"content-type":"application/json"},body:JSON.stringify(body)});
 return response.json();
};
const fixture=await startCaptureFixture();
const transport=new StdioClientTransport({command:process.execPath,args:[entry,"--browser",alias,"mcp"],env,stderr:"pipe"});
const client=new Client({name:"windows-alias-acceptance",version:"1.0"});
const report={source:process.env.KELPIE_CAPTURE_SOURCE,launchId:r.launchId,checks:[]};
const parse=value=>{const v=JSON.parse(value.content.find(c=>c.type==="text").text);return v.value??v.result??v;};
try {
 await client.connect(transport);
 const tools=await client.listTools();assert.ok(tools.tools.some(t=>t.name==="kelpie_extension"));
 const call=async(name,args)=>parse(await client.callTool({name:"kelpie_extension",arguments:{name,arguments:args}}));
 const status=await call("kelpie_get_script_status",{});assert.equal(status.success,true);assert.ok(status.supportedVersions.includes(1));
 const tabs=await api("get-tabs");const tabId=tabs.tabs.find(t=>t.active).id;
 const played=await call("kelpie_play_script",{version:1,tabId,actions:[{action:"navigate",url:fixture.url},
 {action:"wait-ready",state:"complete",selector:"#unique",timeoutMs:10000},
 {action:"click",target:{role:"button",name:"Confirm order",exact:true}}]});
 assert.equal(played.success,true);
 report.firstWorkflow={runId:played.runId,serverEventsBeforeFlush:fixture.events.length};
 const flushed=await api("evaluate",{tabId,expression:"window.captureFixture.flush().then(()=>true)"});
 assert.equal(flushed.success,true);assert.equal(flushed.result,true);
 report.firstWorkflow.serverEventsAfterFlush=fixture.events.length;
 assert.ok(fixture.events.some(e=>e.type==="click"&&e.trusted));
 report.checks.push({name:"public --browser alias stdio MCP workflow",passed:true,runId:played.runId});
 await api("evaluate",{tabId,expression:"document.querySelector('textarea').scrollIntoView({block:'center'});true"});
 const recipe=resolve(output,"recipe.json"),inputs=resolve(output,"inputs.json");
 await writeFile(inputs,JSON.stringify({message:"Bound recipe input"}));
 await writeFile(recipe,JSON.stringify({version:1,tabId,inputs:{message:{type:"string",required:true}},actions:[
 {action:"fill",target:{label:"Draft message",exact:true},text:{input:"message"}},
 {action:"type",target:{label:"Draft message",exact:true},text:" appended"},{action:"press-key",key:"Enter"},
 {action:"screenshot",name:"bound-input"}],capture:{formats:["gif","video","screenshots"],maxWidth:640,maxBytes:8388608}}));
 const result=await cli(["script","run",recipe,"--inputs",inputs,"--output",resolve(output,"download")]);
 await writeFile(resolve(output,"cli-result.json"),JSON.stringify(result,null,2));
 const valueResult=result.result??result;assert.equal(valueResult.success,true,JSON.stringify(valueResult.error));
 const value=await api("evaluate",{tabId,expression:"document.querySelector('textarea').value"});
 assert.equal(value.result,"Bound recipe input appended\n");
 report.checks.push({name:"public alias recipe typed input and artifact download",passed:true,result});

 const secretRecipe=resolve(output,"secret-recipe.json");
 await writeFile(secretRecipe,JSON.stringify({version:1,tabId,actions:[
   {action:"fill",target:{label:"Draft message",exact:true},text:{secret:"vault"}},
   {action:"navigate",url:fixture.url+"/?echo=Aa%20b%2b!"},
   {action:"output",name:"echo",source:"url"}]}));
 const secretResult=await cli(["script","run",secretRecipe,"--secret","vault=KELPIE_CAPTURE_TEST_SECRET"],
   {KELPIE_CAPTURE_TEST_SECRET:"Aa b+!"});
 assert.equal(secretResult.success,true);
 assert.ok(secretResult.outputs.echo.toLowerCase().includes("[redacted]"));
 assert.ok(!JSON.stringify(secretResult).includes("Aa%20b%2b!"));
 report.checks.push({name:"public alias host secret binding and encoded output redaction",passed:true,runId:secretResult.runId});
 const blockedRecipe=resolve(output,"blocked-secret-capture.json");
 await writeFile(blockedRecipe,JSON.stringify({version:1,tabId,actions:[
   {action:"navigate",url:fixture.url+"/next"},
   {action:"fill",target:{label:"Draft message",exact:true},text:{secret:"vault"}}],capture:{formats:["gif"]}}));
 const before=await api("get-current-url",{tabId});let refused=false;
 try {await cli(["script","run",blockedRecipe,"--secret","vault=KELPIE_CAPTURE_TEST_SECRET"],{KELPIE_CAPTURE_TEST_SECRET:"Aa b+!"});}
 catch {refused=true;}
 assert.equal(refused,true);assert.deepEqual(await api("get-current-url",{tabId}),before);
 report.checks.push({name:"public alias secret capture refused before earlier navigation",passed:true});
} catch(error) {report.checks.push({name:"alias acceptance",passed:false,error:error.message});process.exitCode=1;}
finally {
 await client.close();
 await writeFile(resolve(output,"report.json"),JSON.stringify(report,null,2));
 try {await fixture.close();report.cleanup="closed";}
 catch(error){report.cleanup="failed";report.checks.push({name:"fixture cleanup",passed:false,error:error.message});process.exitCode=1;}
 await writeFile(resolve(output,"report.json"),JSON.stringify(report,null,2));
}
console.log(JSON.stringify({passed:report.checks.filter(c=>c.passed).length,failed:report.checks.filter(c=>!c.passed).map(c=>c.error)}));
