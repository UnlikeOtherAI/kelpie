import assert from "node:assert/strict";
import {createConnection,createServer,isIP} from "node:net";
import {networkInterfaces} from "node:os";

export function validateProbe(mode,local,nonlocal){
 assert.ok(["inside","outside"].includes(mode));
 assert.equal(local,"connected","LOOPBACK_PROBE_FAILED");
 if(mode==="outside")assert.equal(nonlocal,"connected","HOST_CANARY_UNREACHABLE");
 else assert.ok(["EACCES","EPERM"].includes(nonlocal),"NONLOOPBACK_NOT_DENIED");
 return {local:"connected",nonlocal:mode==="inside"?"denied":"connected"};
}
const classifiedErrors=new Set(["EACCES","EPERM","ECONNREFUSED","ECONNRESET",
 "ENETUNREACH","EHOSTUNREACH","EADDRNOTAVAIL","ETIMEDOUT"]);
export function classifySocketError(code){return classifiedErrors.has(code)?code:"OTHER";}
function connection(host,port){
 return new Promise(resolve=>{
  const socket=createConnection({host,port});
  let done=false;
  const finish=result=>{if(done)return;done=true;socket.destroy();resolve(result);};
  socket.setTimeout(1500);
  socket.once("connect",()=>finish("connected"));
  socket.once("timeout",()=>finish("timeout"));
  socket.once("error",error=>finish(classifySocketError(error.code)));
 });
}
export async function observeWorkerBoundary(host,port){
 assert.equal(isIP(host),4);
 assert.ok(!host.startsWith("127.")&&host!=="0.0.0.0","Require non-loopback host address");
 assert.ok(Object.values(networkInterfaces()).flat().some(item=>item&&!item.internal&&item.address===host),
  "Canary must target this host");
 assert.ok(Number.isSafeInteger(port)&&port>0&&port<=65535);
 return {local:await connection("127.0.0.1",port),nonlocal:await connection(host,port)};
}

export async function probeWorkerBoundary(host,port,mode){
 const observed=await observeWorkerBoundary(host,port);
 return validateProbe(mode,observed.local,observed.nonlocal);
}
export async function observePrivateBoundary(host,port){
 assert.equal(isIP(host),4);assert.ok(!host.startsWith("127.")&&host!=="0.0.0.0");
 assert.ok(Number.isSafeInteger(port)&&port>0&&port<=65535);
 const server=createServer(socket=>socket.destroy());
 await new Promise((ok,bad)=>{server.once("error",bad);server.listen(0,"127.0.0.1",ok);});
 try{return {local:await connection("127.0.0.1",server.address().port),nonlocal:await connection(host,port)};}
 finally{await new Promise(ok=>server.close(ok));}
}
export function validatePrivateProbe(local,nonlocal){
 assert.equal(local,"connected","LOOPBACK_PROBE_FAILED");
 assert.ok(["EACCES","EPERM","ENETUNREACH","EHOSTUNREACH"].includes(nonlocal),"NONLOOPBACK_NOT_DENIED");
 return {local:"connected",nonlocal:"denied"};
}
