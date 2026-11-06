import {spawn} from "node:child_process";
import {readFile,writeFile} from "node:fs/promises";
import path from "node:path";
import {comparisonReason,safeArmFailures} from "../../tests/macos/runtime-png-compare.mjs";
if(process.env.GITHUB_ACTIONS!=="true"||process.env.RUNNER_OS!=="macOS"||process.env.KELPIE_HOSTED_RUNTIME!=="1")throw new Error("DEDICATED_HOSTED_RUNNER_REQUIRED");
const arms=[["png-a1","0"],["png-b1","1"],["png-b2","1"],["png-a2","0"]],reports=[];
for(const [label,mode] of arms){
 const status=await new Promise((resolve,reject)=>{
  const child=spawn(process.execPath,["scripts/testing/macos-workflow-acceptance.mjs"],{stdio:"inherit",env:{...process.env,KELPIE_RUNTIME_SCOPE:"cef-png-equivalence",KELPIE_EVIDENCE_LABEL:label,KELPIE_CEF_PNG_SPEED_TEST:mode}});
  child.once("error",reject);child.once("exit",(code,signal)=>resolve({code,signal}));
 });
 let report=null;try{report=JSON.parse(await readFile(path.join(".cache/macos-runtime/evidence",label,"report.json"),"utf8"));}catch{}
 reports.push({label,mode,status,report});
 // Preserve the real failure and never launch another app if cleanup is unverified.
 if(!report?.ownedChildExited||!report?.ownedListenersReleased)break;
}
const reason=comparisonReason(reports);
const extract=arm=>arm.report.engines?.find(x=>x.engine==="chromium")?.checks?.filter(x=>x.name.startsWith("png-equivalence-")).map(x=>x.detail);
const receipt={version:1,scope:"synthetic-composited-export-equivalence",passed:reason===null,reason,sourceAlphaProven:false,arms:reports.map(({label,mode,status,report})=>({label,mode,status,cleanup:!!report?.ownedChildExited&&!!report?.ownedListenersReleased,failures:safeArmFailures(report),source:report?.source??null,executableHash:report?.executableHash??null,debugLibraryHash:report?.debugLibraryHash??null,cefFrameworkHash:report?.cefFrameworkHash??null,cases:report?extract({report})??[]:[]}))};
await writeFile(".cache/macos-runtime/evidence/png-equivalence-comparison.json",JSON.stringify(receipt,null,2),{flag:"wx"});
if(reason)process.exitCode=1;
