// Startup-only diagnostics: no fixture, model, pairing grant or raw log is retained.
import {execFileSync} from "node:child_process";
import {mkdir,open,readdir,stat} from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import {listeners} from "./runtime-client.mjs";
function command(file,args,timeout=3000){
 try{return execFileSync(file,args,{encoding:"utf8",timeout,maxBuffer:1048576,stdio:["ignore","pipe","pipe"]});}
 catch{return null;}
}
async function prefix(file,maximum){
 const handle=await open(file,"r");try{const buffer=Buffer.alloc(maximum),{bytesRead}=await handle.read(buffer,0,maximum,0);return buffer.subarray(0,bytesRead).toString("utf8");}
 finally{await handle.close();}
}
function symbol(value){return String(value??"").replace(/[^A-Za-z0-9_ .:<>()\[\]$+*,-]/g,"").slice(0,220);}
function fixed(value,pattern){return typeof value==="string"&&pattern.test(value)?value:undefined;}
export async function bootstrapDiagnostics({pid,executable,started,privateDir}){
 if(!Number.isSafeInteger(pid)||pid<=1)return {spawned:false};
 const output={spawned:true,ports:{http:listeners(28420),appReveal:listeners(8421)}};
 const mapping=command("/usr/sbin/lsof",["-a","-p",String(pid),"-d","txt","-Fn"]);
 output.mappedExecutableMatches=mapping?.split("\n").includes("n"+executable)??false;
 output.debugLibraryMapped=mapping?.includes("/Kelpie.debug.dylib")??false;
 const ownedPorts=command("/usr/sbin/lsof",["-nP","-a","-p",String(pid),"-iTCP","-sTCP:LISTEN","-Fn"]);
 output.ownedListenPorts=[...new Set((ownedPorts??"").split("\n").filter(line=>line.startsWith("n")).flatMap(line=>{
  const match=line.match(/:(\d+)$/);return match?[Number(match[1])]:[];
 }))].slice(0,32);
 const state=command("/bin/ps",["-p",String(pid),"-o","stat=,ppid=,pgid=,etime="]);
 output.processAlive=Boolean(state?.trim());
 output.processState=state?.trim().replace(/[^A-Za-z0-9 :+-]/g,"").slice(0,128);
 if(output.mappedExecutableMatches){
  await mkdir(privateDir,{recursive:true,mode:0o700});
  const samplePath=path.join(privateDir,"startup.sample.txt");
  output.sampleCaptured=command("/usr/bin/sample",[String(pid),"1","1","-file",samplePath],5000)!==null;
  if(output.sampleCaptured){
   try{const sample=await prefix(samplePath,4194304);
   output.sampleSymbols=[...new Set(sample.split("\n").flatMap(line=>{
    const match=line.match(/\d+\s+(.{1,400}?)\s+\(in ([A-Za-z0-9_.+-]{1,80})\)/);
    return match?[symbol(match[1])+" (in "+match[2]+")"]:[];
   }))].slice(0,160);
   }catch{output.sampleCaptured=false;}
  }
 }
 const directory=path.join(os.homedir(),"Library/Logs/DiagnosticReports");
 try{
  const names=(await readdir(directory)).filter(name=>name.startsWith("Kelpie-")&&name.endsWith(".ips")).sort().reverse().slice(0,16);
  output.crashDirectoryAvailable=true;output.crashes=[];
  for(const name of names){
   const file=path.join(directory,name),info=await stat(file);
   if(info.mtimeMs<started||info.size>8388608)continue;
   const text=await prefix(file,8388608),newline=text.indexOf("\n");let crash;
   try{crash=JSON.parse(text.slice(newline+1));}catch{continue;}
   if(crash.pid!==pid||crash.procPath!==executable)continue;
   const frames=crash.threads?.[crash.faultingThread]?.frames??[];
   output.crashes.push({pid,exceptionType:fixed(crash.exception?.type,/^[A-Z_]{1,64}$/),
    signal:fixed(crash.exception?.signal,/^[A-Z0-9_]{1,32}$/),
    namespace:fixed(crash.termination?.namespace,/^[A-Z0-9_ ]{1,64}$/),
    code:Number.isSafeInteger(crash.termination?.code)?crash.termination.code:undefined,
    faultingSymbols:frames.slice(0,60).map(frame=>symbol(frame.symbol)).filter(Boolean)});
  }
 }catch{output.crashDirectoryAvailable=false;}
 return output;
}
