import assert from "node:assert/strict";
import {spawn,execFile} from "node:child_process";
import {promisify} from "node:util";
import {createHash} from "node:crypto";
import {mkdir,readFile,writeFile} from "node:fs/promises";
import {isAbsolute,join} from "node:path";
import {createInterface} from "node:readline";
import {whiteBackedRGB} from "./wgc-g08-rgb.mjs";
import {safeWgcDiagnostic} from "./wgc-safe-diagnostic.mjs";
import {alphaControlWgcArgs} from "./wgc-alpha-control-args.mjs";

const [control,wgc,ffmpeg,output,controlHash,wgcHash,revision]=process.argv.slice(2);
assert.ok([control,wgc,ffmpeg,output].every(value=>value&&isAbsolute(value)));
assert.ok([controlHash,wgcHash].every(value=>/^[a-f0-9]{64}$/.test(value??"")));
assert.match(revision??"",/^[a-f0-9]{40}$/);
const hash=async path=>createHash("sha256").update(await readFile(path)).digest("hex");
assert.equal(await hash(control),controlHash);assert.equal(await hash(wgc),wgcHash);
await mkdir(output,{recursive:false});
const report={source:revision,stage:"start",checks:[],cleanup:"not-started",hashes:{control:controlHash,wgc:wgcHash,ffmpeg:await hash(ffmpeg)}};
let child,closed;
const exec=promisify(execFile);
try{
 assert.equal((await exec("git.exe",["rev-parse","HEAD"],{windowsHide:true,timeout:10000})).stdout.trim(),revision);
 child=spawn(control,[],{windowsHide:true,stdio:["ignore","pipe","ignore"]});
 closed=new Promise((resolve,reject)=>{child.once("error",reject);child.once("exit",(code,signal)=>resolve({code,signal}));});
 void closed.catch(()=>{});
 const lines=createInterface({input:child.stdout});
 const iterator=lines[Symbol.asyncIterator]();
 const first=await Promise.race([iterator.next(),new Promise((_,reject)=>setTimeout(()=>reject(new Error("CONTROL_READY_TIMEOUT")),4000))]);
 assert.equal(first.done,false);assert.ok(first.value.length<512);
 const identity=JSON.parse(first.value);
 assert.equal(identity.pid,child.pid);assert.match(identity.startFileTime,/^\d+$/);assert.match(identity.hwnd,/^\d+$/);
 report.identity=identity;report.stage="wgc";
 await exec(wgc,alphaControlWgcArgs(identity,control,join(output,"capture")),
  {windowsHide:true,timeout:10000,maxBuffer:131072});
 const meta=JSON.parse(await readFile(join(output,"capture","metadata.json"),"utf8"));
 assert.equal(meta.processId,identity.pid);assert.equal(meta.windowHandle,identity.hwnd);
 assert.equal(meta.width,320);assert.equal(meta.height,160);assert.equal(meta.cursorCapture,false);
 assert.equal(meta.raw.sha256,await hash(join(output,"capture","frame.bgra")));
 assert.equal(meta.png.sha256,await hash(join(output,"capture","frame.png")));
 const raw=await readFile(join(output,"capture","frame.bgra"));assert.equal(raw.length,320*160*4);
 const decoded=(await exec(ffmpeg,["-v","error","-i",join(output,"capture","frame.png"),"-f","rawvideo","-pix_fmt","rgba","-"],
  {windowsHide:true,timeout:10000,maxBuffer:320*160*4+4096,encoding:"buffer"})).stdout;
 assert.equal(decoded.length,320*160*4);
 const patches=[["red",50,[0,0,178,178]],["green",150,[0,89,0,89]],["blue",250,[255,0,0,255]],["clear",310,[0,0,0,0]]].map(([name,x,inputBgra])=>{
  const samples=[];for(let y=79;y<=81;y++)for(let xx=x-1;xx<=x+1;xx++){
   const at=(y*320+xx)*4;
   const pixel=raw.subarray(at,at+4);let premultiplied=null;
   try{premultiplied=[...whiteBackedRGB(pixel,1,1,"premultiplied")];}catch{}
   samples.push({rawBgra:[...pixel],pngRgba:[...decoded.subarray(at,at+4)],
    whiteStraight:[...whiteBackedRGB(pixel,1,1,"straight")],whitePremultiplied:premultiplied});
  }
  return {name,x,y:80,inputBgra,samples};
 });
 report.meta={width:meta.width,height:meta.height,alphaMode:meta.alphaMode,raw:meta.raw,png:meta.png};
 report.patches=patches;report.checks.push({name:"owned WGC control captured",passed:true});report.stage="natural-exit";
 report.exit=await Promise.race([closed,new Promise((_,reject)=>setTimeout(()=>reject(new Error("CONTROL_EXIT_TIMEOUT")),18000))]);
 assert.equal(report.exit.code,0);report.cleanup="natural-exit";
}catch(error){
 report.failure={stage:report.stage,category:["AssertionError","Error","TypeError"].includes(error.name)?error.name:"Other",
  ...(report.stage==="wgc"?{diagnostic:safeWgcDiagnostic(error.stderr),code:typeof error.code==="number"?error.code:null,signal:error.signal??null,killed:error.killed===true}:{})};
 process.exitCode=1;
}finally{
 if(child&&child.exitCode===null){child.kill();try{report.forcedExit=await closed;}catch{}}
 await writeFile(join(output,"report.json"),JSON.stringify(report,null,2),{flag:"wx"});
}
