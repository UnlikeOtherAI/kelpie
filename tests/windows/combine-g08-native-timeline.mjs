import assert from "node:assert/strict";
import {execFile} from "node:child_process";
import {promisify} from "node:util";
import {createHash} from "node:crypto";
import {readFile,writeFile,mkdir,lstat} from "node:fs/promises";
import {resolve,dirname,join,isAbsolute} from "node:path";
import {fileURLToPath} from "node:url";
import {verifyWgcProvenance} from "./wgc-g08-provenance.mjs";
import {verifyTimelineSnapshots} from "./wgc-case-files.mjs";
import {compareMeasuredPhases} from "./wgc-g08-compare.mjs";
import {evaluateG08} from "../capture/g08-timeline.mjs";
const [cPath,cHash,cReportHash,sPath,sHash,sReportHash,output,expectedRevision,expectedUiaHash,expectedWgcHash]=process.argv.slice(2);
assert.ok([cPath,sPath,output].every(p=>p&&isAbsolute(p)));for(const v of [cHash,cReportHash,sHash,sReportHash])assert.match(v??"",/^[a-f0-9]{64}$/);
assert.match(expectedRevision??"",/^[a-f0-9]{40}$/);assert.match(expectedUiaHash??"",/^[a-f0-9]{64}$/);assert.match(expectedWgcHash??"",/^[a-f0-9]{64}$/);
const exec=promisify(execFile),repo=fileURLToPath(new URL("../../",import.meta.url));
const run=(command,args,timeout=30000)=>exec(command,args,{windowsHide:true,timeout,maxBuffer:2097152});
assert.equal((await run("git",["-C",repo,"rev-parse","HEAD"])).stdout.trim(),expectedRevision);
assert.equal((await run("git",["-C",repo,"status","--porcelain","--untracked-files=no"])).stdout.trim(),"");
await mkdir(output,{recursive:false});
const digest=bytes=>createHash("sha256").update(bytes).digest("hex");
const report={testRevision:expectedRevision,phase:"cases",checks:[]};
async function loadCase(path,expectedCase,expectedReport,curve){
 const info=await lstat(path);assert.ok(info.isFile()&&!info.isSymbolicLink()&&info.size<=67108864);
 const bytes=await readFile(path);assert.equal(digest(bytes),expectedCase);const value=JSON.parse(bytes.toString("utf8"));
 const dir=dirname(path),reportPath=join(dir,"report.json"),runReport=await readFile(reportPath);assert.equal(digest(runReport),expectedReport);
 const observed=JSON.parse(runReport.toString("utf8"));assert.equal(observed.source,value.facts.source);assert.equal(observed.curve,curve);
 assert.equal(observed.cleanup,"supported-cli-closed");assert.equal(observed.processExit?.exited,true);
 assert.equal(observed.testRevision,expectedRevision);assert.equal(observed.hashes?.uia,expectedUiaHash);assert.equal(observed.hashes?.wgc,expectedWgcHash);assert.equal(observed.hashes?.dll,value.binarySHA256);
 assert.ok(observed.checks.some(check=>check.name==="owned native and exported G08 case"&&check.passed===true));
 assert.equal(value.curve,curve);assert.equal(value.profile,"dense");assert.match(value.binarySHA256,/^[a-f0-9]{64}$/);
 const provenance=verifyWgcProvenance(value.facts);assert.deepEqual(provenance,value.provenance);
 assert.deepEqual(value.scene,{calibration:value.facts.fixture.events[0],start:value.facts.fixture.events[1],finish:value.facts.fixture.events[2]});
 await verifyTimelineSnapshots(value.summary,join(dir,"native"));
 assert.deepEqual(value.summary,value.facts.summary);
 for(const item of value.artifacts){
  const extension=item.mimeType==="image/gif"?".gif":item.mimeType==="video/mp4"?".mp4":null;assert.ok(extension);
  assert.equal(resolve(item.file),resolve(dir,item.id+extension));const entry=await lstat(item.file);assert.ok(entry.isFile()&&!entry.isSymbolicLink());
  assert.equal(entry.size,item.byteLength);assert.equal(digest(await readFile(item.file)),item.sha256);
 }
 assert.deepEqual(value.artifacts,value.facts.artifacts);
 const samples=value.native.samples.map(sample=>{
  const marker={...sample.marker};
  if(typeof marker.roi==="string"){assert.ok(marker.roi.length<=4096000);const decoded=Buffer.from(marker.roi,"base64");assert.equal(decoded.toString("base64"),marker.roi);marker.roi=decoded;}
  return {...sample,marker};
 });
 assert.equal(samples.length,value.native.frameCount);assert.equal(samples.length,value.facts.frameCount);
 const config={...value.config,scale:{x:provenance.width/value.config.viewport.width,y:provenance.height/value.config.viewport.height}};
 assert.equal(config.curve,curve);assert.deepEqual(config.from,value.scene.start.center);assert.deepEqual(config.to,value.scene.finish.center);
 const analysis=evaluateG08(samples,config);
 return {value,provenance,samples,analysis};
}
try{
 const c=await loadCase(cPath,cHash,cReportHash,"c"),s=await loadCase(sPath,sHash,sReportHash,"s");
 assert.equal(c.provenance.source,s.provenance.source);assert.equal(c.value.binarySHA256,s.value.binarySHA256);
 const input={source:c.provenance.source,binarySHA256:c.value.binarySHA256,runtime:"windows-cef",eventsDropped:0,
  cases:[c,s].map(item=>({curve:item.value.curve,scene:item.value.scene,artifacts:item.value.artifacts}))};
 const inputPath=join(output,"export-input.json"),outputPath=join(output,"export-oracle.json");
 await writeFile(inputPath,JSON.stringify(input,null,2),{flag:"wx"});report.phase="export-oracle";
 await run(process.execPath,[join(repo,"tests/capture/g08-verify.mjs"),inputPath,outputPath],180000);
 const exportBytes=await readFile(outputPath),verified=JSON.parse(exportBytes.toString("utf8"));
 assert.equal(verified.source,input.source);assert.equal(verified.binarySHA256,input.binarySHA256);assert.equal(verified.runtime,input.runtime);
 assert.equal(verified.results.length,4);assert.ok(verified.results.every(item=>item.passed===true));
 const comparisons=[];
 for(const item of [c,s])for(const artifact of item.value.artifacts){
  const matches=verified.results.filter(result=>result.curve===item.value.curve&&result.id===artifact.id&&result.sha256===artifact.sha256&&result.mimeType===artifact.mimeType);
  assert.equal(matches.length,1);const comparison=compareMeasuredPhases({provenance:item.provenance,samples:item.samples,analysis:item.analysis},
   {provenance:item.provenance,samples:matches[0].samples,analysis:matches[0].analysis});
  comparisons.push({curve:item.value.curve,id:artifact.id,mimeType:artifact.mimeType,...comparison});
 }
 report.phase="complete";report.checks.push({name:"same-run native and export relative phases",passed:true,comparisons});
 report.exportOracleSha256=digest(exportBytes);report.exportInputSha256=digest(await readFile(inputPath));
}catch(error){
 const message=String(error.message??"");
 const category=/^(INSUFFICIENT_EVIDENCE|G08_|WGC_)[A-Za-z0-9_ .:-]{0,120}$/.test(message)&&!/[a-f0-9]{24,}/i.test(message)?message:"COMBINE_FAILED";
 report.checks.push({name:"same-run native and export relative phases",passed:false,stage:report.phase,category});process.exitCode=1;
}finally{await writeFile(join(output,"report.json"),JSON.stringify(report,null,2),{flag:"wx"});}
