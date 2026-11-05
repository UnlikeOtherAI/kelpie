import assert from "node:assert/strict";
import {readFile,writeFile} from "node:fs/promises";
import {randomUUID} from "node:crypto";
import {nativeWindowFixtureExpression} from "./native-window-fixture.mjs";
const [readinessPath,outputPath]=process.argv.slice(2);
const r=JSON.parse(await readFile(readinessPath,"utf8")),report={checks:[]};
const api=async(method,body={})=>{
 const response=await fetch("http://127.0.0.1:"+r.port+"/v1/"+method,{method:"POST",
  headers:{authorization:"Bearer "+r.token,"content-type":"application/json"},body:JSON.stringify(body),
  signal:AbortSignal.timeout(15000)});
 return response.json();
};
try{
 const navigated=await api("navigate",{url:"about:blank"});
 report.navigation={success:navigated.success,errorCode:navigated.error?.code};
 assert.equal(navigated.success,true);
 const tabs=await api("get-tabs"),tabId=tabs.tabs.find(t=>t.active).id;
 const environment=await api("evaluate",{tabId,expression:"({secure:isSecureContext,uuidType:typeof crypto.randomUUID,location:location.href,body:!!document.body})"});
 report.environment=environment.result;assert.equal(environment.success,true);
 const old=await api("evaluate",{tabId,expression:"crypto.randomUUID()"});
 report.oldPrimitive={success:old.success,errorCode:old.error?.code};
 const id=randomUUID();
 const oldPrepared=await api("evaluate",{tabId,expression:nativeWindowFixtureExpression(id).replace(JSON.stringify(id),"crypto.randomUUID()")});
 report.oldPrepared={success:oldPrepared.success,errorCode:oldPrepared.error?.code};
 const fixed=await api("evaluate",{tabId,expression:nativeWindowFixtureExpression(id)});
 report.fixed={success:fixed.success,errorCode:fixed.error?.code,scene:fixed.result};
 assert.equal(fixed.success,true);assert.equal(fixed.result.documentId,id);
 report.checks.push({name:"Node fixture identity works independently of page secure-context APIs",passed:true});
}catch(error){report.checks.push({name:"fixture preparation diagnosis",passed:false,error:error.message});process.exitCode=1;}
finally{await writeFile(outputPath,JSON.stringify(report,null,2));}
console.log(JSON.stringify(report));
