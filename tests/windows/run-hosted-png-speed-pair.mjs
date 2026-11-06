import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {execFile} from "node:child_process";
import {mkdir,readFile,writeFile} from "node:fs/promises";
import {join,resolve} from "node:path";
import {promisify} from "node:util";
import {pathToFileURL} from "node:url";
import {runPngSpeedPair} from "./png-speed-serial.mjs";

export function classifyOracle(result){
 assert.ok(Array.isArray(result.results)&&result.results.length===2);
 if(result.results.every(item=>item.passed===true))return "pass";
 if(result.results.some(item=>item.passed!==true&&item.confidence!=="insufficient"))return "fail";
 return "insufficient";
}
async function main(){
 assert.ok(process.env.RUNNER_TEMP&&/^[a-f0-9]{40}$/i.test(process.env.GITHUB_SHA||""));
 const root=join(process.env.RUNNER_TEMP,"kelpie-hosted-png-ab"),repo=resolve("."),build=join(repo,".cache/windows-release3");
 const exe=join(build,"kelpie.exe"),dll=join(build,"kelpie.dll"),script=join(repo,"scripts/run-hosted-windows-g08.ps1");
 const sha=async path=>createHash("sha256").update(await readFile(path)).digest("hex");
 const cache=await readFile(join(build,"CMakeCache.txt"),"utf8");
 assert.match(cache,/^KELPIE_TEST_SCRIPT_PNG_SPEED:BOOL=ON\r?$/m);
 const expectedBinary=await sha(dll),expectedExe=await sha(exe),exec=promisify(execFile);
 await mkdir(root,{recursive:false});let referenceAssets=null,currentArm="preflight",outcome="failed";
 const runArm=async arm=>{
  currentArm=arm;assert.equal(await sha(dll),expectedBinary);assert.equal(await sha(exe),expectedExe);
  const directory=join(root,arm);await mkdir(directory,{recursive:false});
  const env={...process.env,RUNNER_TEMP:directory,KELPIE_HOSTED_PNG_AB:arm};
  let wrapperExit=0;
  try{await exec("powershell.exe",["-NoProfile","-NonInteractive","-File",script],
   {env,windowsHide:true,timeout:420000,maxBuffer:1048576});}catch(error){wrapperExit=typeof error.code==="number"?error.code:-1;}
  const evidence=join(directory,"kelpie-hosted-g08-evidence");
  const read=async name=>JSON.parse(await readFile(join(evidence,name),"utf8"));
  const [manifest,diagnostic,cleanup]=await Promise.all([read("manifest.json"),read("diagnostic.json"),read("hosted-cleanup.json")]);
  assert.equal(manifest.source,process.env.GITHUB_SHA);assert.equal(manifest.dllSha256,expectedBinary);assert.equal(manifest.exeSha256,expectedExe);
  assert.equal(await sha(dll),expectedBinary);assert.equal(await sha(exe),expectedExe);
  const assets=JSON.stringify(manifest.assets);if(referenceAssets===null)referenceAssets=assets;else assert.equal(assets,referenceAssets);
  assert.equal(diagnostic.pngArm,arm);assert.equal(diagnostic.identity?.pid,cleanup.spawnPid);
  const oracle=classifyOracle(await read("hosted/oracle-output.json"));
  assert.ok(Array.isArray(diagnostic.captureStages)&&diagnostic.captureStages.length>0);
  assert.ok(Array.isArray(diagnostic.pngByteReceipts)&&diagnostic.pngByteReceipts.some(item=>item.count>0));
  return {arm,dllSha256:manifest.dllSha256,exeVerified:true,processAbsent:cleanup.pidPresent===false,
   listenerAbsent:cleanup.listenerPresent===false,readinessAbsent:diagnostic.readinessAbsent===true,
   closedPublicly:diagnostic.cleanup==="public-close-exited",caseFinished:diagnostic.casePassed===true,
   oracle,wrapperExit,peakScope:"app-pid-only; process-tree-and-job-unavailable"};
 };
 try{
  const pair=await runPngSpeedPair({expectedBinary,runArm});outcome="completed";
  await writeFile(join(root,"pair.json"),JSON.stringify({source:process.env.GITHUB_SHA,expectedBinary,expectedExe,
   scope:"dense-export-only; no-pixel-or-alpha-equivalence",...pair},null,2),{flag:"wx"});
 }finally{
  await writeFile(join(root,"outcome.json"),JSON.stringify({status:outcome,lastArm:currentArm,
   scope:"dense-export-only; no-pixel-or-alpha-equivalence"},null,2),{flag:"wx"});
 }
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)await main();
