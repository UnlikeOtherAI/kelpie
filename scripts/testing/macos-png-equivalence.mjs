import {spawn} from "node:child_process";
import {readFile,writeFile} from "node:fs/promises";
import path from "node:path";
import {isDeepStrictEqual} from "node:util";
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
let reason=null;
if(reports.length!==4||reports.some(x=>x.status.code!==0||x.status.signal||!x.report?.focusedScopePassed))reason="ARM_FAILED";
const extract=arm=>arm.report.engines.find(x=>x.engine==="chromium")?.checks.filter(x=>x.name.startsWith("png-equivalence-")).map(x=>x.detail);
if(!reason){
 const first=reports[0].report;
 if(reports.some(x=>x.report.source!==first.source||x.report.executableHash!==first.executableHash||x.report.debugLibraryHash!==first.debugLibraryHash||x.report.cefFrameworkHash!==first.cefFrameworkHash))reason="BINARY_MISMATCH";
 const baseline=extract(reports[0]);
 if(baseline?.length===3&&new Set(baseline.map(x=>x.rgbaSHA256)).size!==3)reason="FIXTURE_NOT_DISTINCT";
 if(!baseline||baseline.length!==3||reports.some(arm=>{const facts=extract(arm);return !facts||facts.length!==3||facts.some((x,i)=>!isDeepStrictEqual({name:x.name,width:x.width,height:x.height,hash:x.rgbaSHA256,alpha:x.alpha},{name:baseline[i].name,width:baseline[i].width,height:baseline[i].height,hash:baseline[i].rgbaSHA256,alpha:baseline[i].alpha}));}))reason="PIXEL_MISMATCH";
}
const receipt={version:1,scope:"synthetic-composited-export-equivalence",passed:reason===null,reason,sourceAlphaProven:false,arms:reports.map(({label,mode,status,report})=>({label,mode,status,cleanup:!!report?.ownedChildExited&&!!report?.ownedListenersReleased,source:report?.source??null,executableHash:report?.executableHash??null,cases:report?extract({report})??[]:[]}))};
await writeFile(".cache/macos-runtime/evidence/png-equivalence-comparison.json",JSON.stringify(receipt,null,2),{flag:"wx"});
if(reason)process.exitCode=1;
