import assert from "node:assert/strict";
import {readFile,readdir,readlink} from "node:fs/promises";
import {parseProcStat} from "./native-resource-snapshot.mjs";

// Only an IPv4 loopback listener on the reserved port qualifies.
export function loopbackListenerInodes(table,port){
 assert.ok(Number.isInteger(port)&&port>0&&port<=65535);
 const found=new Set();
 for(const line of table.split("\n").slice(1)){
  const fields=line.trim().split(/\s+/),local=fields[1]?.split(":");
  if(local?.[0]==="0100007F"&&parseInt(local[1],16)===port&&fields[3]==="0A"&&/^\d+$/.test(fields[9]??""))
   found.add(fields[9]);
 }
 return found;
}
async function stat(pid){
 try{return parseProcStat(await readFile("/proc/"+pid+"/stat","utf8"));}catch{return null;}
}
export async function verifyOwnedListener(pid,port,expectedStart){
 assert.match(expectedStart??"",/^\d+$/);
 const before=await stat(pid);assert.ok(before&&before.startTicks===expectedStart,"ENGINE_IDENTITY_UNAVAILABLE");
 const inodes=loopbackListenerInodes(await readFile("/proc/net/tcp","utf8"),port);
 assert.ok(inodes.size>0,"ENGINE_LISTENER_MISSING");
 const files=await readdir("/proc/"+pid+"/fd");assert.ok(files.length<=8192,"ENGINE_FD_LIMIT");
 let owned=false;
 for(const fd of files){
  try{const target=await readlink("/proc/"+pid+"/fd/"+fd);
   const match=/^socket:\[(\d+)\]$/.exec(target);if(match&&inodes.has(match[1]))owned=true;
  }catch{/* A transient descriptor does not establish ownership. */}
 }
 const after=await stat(pid);
 assert.ok(after&&after.startTicks===before.startTicks,"ENGINE_IDENTITY_CHANGED");
 assert.ok(owned,"ENGINE_LISTENER_NOT_OWNED");
 return before.startTicks;
}
