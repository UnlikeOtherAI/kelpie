// Private-Weston synthetic ROI stream. No seat, focus, or input interface is used.
import assert from "node:assert/strict";
import { spawn, execFile } from "node:child_process";
import { promisify } from "node:util";
import { createHash } from "node:crypto";
import { mkdir, readFile, realpath, lstat, writeFile } from "node:fs/promises";
import { join, resolve, sep } from "node:path";
import { readNativeIdentity } from "./native-lifecycle.mjs";
import { ownedWaylandViews } from "./wayland-scene-guard.mjs";
const execute=promisify(execFile),hash=bytes=>createHash("sha256").update(bytes).digest("hex");

export async function capturePrivateWestonStream({identity,binary,hash:binaryHash,output,env,signal}) {
 assert.equal(env.KELPIE_ISOLATED_WAYLAND,"1");
 const runtime=resolve(env.XDG_RUNTIME_DIR);assert.ok(runtime.startsWith("/tmp/kelpie-wayland-"));
 const runtimeStat=await lstat(runtime);assert.ok(runtimeStat.isDirectory()&&!runtimeStat.isSymbolicLink());
 assert.equal(runtimeStat.uid,process.getuid());assert.equal(runtimeStat.mode&0o777,0o700);
 assert.ok(env.DBUS_SESSION_BUS_ADDRESS&&!env.DBUS_SESSION_BUS_ADDRESS.includes("/run/user/1000/bus"));
 assert.match(env.WAYLAND_DISPLAY??"",/^kelpie-[a-f0-9]{24}$/);
 const socket=await lstat(join(runtime,env.WAYLAND_DISPLAY));assert.ok(socket.isSocket());assert.equal(socket.uid,process.getuid());
 const weston=JSON.parse(env.KELPIE_PRIVATE_WESTON_IDENTITY);
 const helper=await realpath(env.KELPIE_WESTON_STREAM??"");
 assert.ok(helper.startsWith(resolve(".native-cache")+sep));
 const helperStat=await lstat(helper);assert.ok(helperStat.isFile());assert.equal(helperStat.uid,process.getuid());
 const helperHash=hash(await readFile(helper));assert.equal(helperHash,env.KELPIE_WESTON_STREAM_SHA256);
 const pin=async(full)=>{
  for(const [expected,exe,digest] of [[identity,binary,binaryHash],[weston,"/usr/bin/weston",weston.sha256]]) {
   const actual=await readNativeIdentity(expected.pid);assert.equal(actual?.startTicks,expected.startTicks);
   assert.equal(await realpath("/proc/"+expected.pid+"/exe"),await realpath(exe));
   if(full)assert.equal(hash(await readFile("/proc/"+expected.pid+"/exe")),digest);
  }
 };
 const scene=async()=>{
  await pin(false);const before=process.hrtime.bigint();
  const {stdout}=await execute("/usr/bin/weston-debug",["scene-graph"],{env,signal,timeout:3000,maxBuffer:262144});
  const after=process.hrtime.bigint();
  const views=ownedWaylandViews(stdout,identity.pid);
  return {startNs:before.toString(),endNs:after.toString(),views};
 };
 const directory=join(output,"isolated-wayland-stream");await mkdir(directory,{mode:0o700});
 const report={scope:"ISOLATED_WAYLAND",helperSHA256:helperHash,app:identity,compositor:weston,monitor:[],frames:[],complete:false};
 let child,timer,monitorError,exit;
 try {
  await pin(true);report.before=await scene();
  child=spawn(helper,[directory],{env,stdio:["ignore","pipe","pipe"],signal});
  let stdout="",stderr="",ended=false;
  child.stdout.on("data",data=>{stdout=(stdout+data.toString()).slice(-4096);});
  child.stderr.on("data",data=>{stderr=(stderr+data.toString()).slice(-4096);});
  const closed=new Promise((done,reject)=>{child.once("error",error=>{ended=true;reject(error);});child.once("close",(code,sig)=>{ended=true;done({code,signal:sig});});});
  void closed.catch(()=>{});timer=setTimeout(()=>child.kill("SIGTERM"),8000);
  while(!ended) {
   try {report.monitor.push(await scene());} catch(error){monitorError=error;child.kill("SIGTERM");break;}
   if(report.monitor.length>400){monitorError=Error("MONITOR_LIMIT");child.kill("SIGTERM");break;}
   await new Promise(done=>setTimeout(done,20));
  }
  exit=await closed;report.streamEndNs=process.hrtime.bigint().toString();clearTimeout(timer);if(monitorError)throw monitorError;
  assert.equal(exit.code,0,"STREAM_FAILED "+stderr);report.summary=JSON.parse(stdout);
  assert.ok(Number.isInteger(report.summary.frames)&&report.summary.frames>0&&report.summary.frames<=160);
  const lines=(await readFile(join(directory,"frames.jsonl"),"utf8")).trim().split("\n").map(line=>JSON.parse(line));
  assert.equal(lines.length,report.summary.frames);assert.ok(report.monitor.length>=2);
  const intervals=report.monitor.map(item=>Number(BigInt(item.endNs)-BigInt(item.startNs))/1e6);
  const maxGap=Math.max(...intervals,...report.monitor.slice(1).map((item,index)=>Number(BigInt(item.startNs)-BigInt(report.monitor[index].startNs))/1e6),
    Number(BigInt(report.monitor[0].startNs)-BigInt(report.before.endNs))/1e6,
    Number(BigInt(report.streamEndNs)-BigInt(report.monitor.at(-1).endNs))/1e6);
  report.maxMonitorGapMs=maxGap;assert.ok(maxGap<=200,"MONITOR_GAP");
  for(const [index,row] of lines.entries()) {
   assert.equal(row.index,index);assert.ok(BigInt(row.endNs)>=BigInt(row.startNs));
   if(index)assert.ok(BigInt(row.startNs)>BigInt(lines[index-1].endNs));
   const path=join(directory,"frame-"+String(index).padStart(3,"0")+".bgra"),info=await lstat(path);
   assert.ok(info.isFile()&&!info.isSymbolicLink());assert.equal(info.uid,process.getuid());assert.equal(info.size,256*320*4);
   report.frames.push({...row,file:path,sha256:hash(await readFile(path))});
  }
  report.after=await scene();await pin(true);report.complete=true;return report;
 } finally {
  clearTimeout(timer);if(child&&child.exitCode===null&&child.signalCode===null)child.kill("SIGTERM");
  await writeFile(join(directory,"receipt.json"),JSON.stringify(report,null,2));
 }
}
