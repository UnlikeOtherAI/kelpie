// One owned app at a time, same hosted runner and exact candidate binary.
import {spawn} from "node:child_process";
if(process.env.GITHUB_ACTIONS!=="true"||process.env.RUNNER_OS!=="macOS"||process.env.KELPIE_HOSTED_RUNTIME!=="1")
 throw new Error("DEDICATED_HOSTED_RUNNER_REQUIRED");
let failed=false;
for(const [label,mode] of [["legacy-before","legacy"],["scheduled","scheduled"],["legacy-after","legacy"]]){
 const status=await new Promise((resolve,reject)=>{
  const child=spawn(process.execPath,["scripts/testing/macos-workflow-acceptance.mjs"],{
   stdio:"inherit",env:{...process.env,KELPIE_RUNTIME_SCOPE:"cef-timing",KELPIE_EVIDENCE_LABEL:label,KELPIE_CEF_PUMP_TEST:mode}
  });
  child.once("error",reject);child.once("exit",(code,signal)=>resolve({code,signal}));
 });
 if(status.code!==0||status.signal)failed=true;
}
if(failed)process.exitCode=1;
