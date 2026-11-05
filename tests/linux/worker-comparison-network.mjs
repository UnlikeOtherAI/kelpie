import assert from "node:assert/strict";
import {createConnection,isIP} from "node:net";
import {networkInterfaces} from "node:os";

export function validateProbe(mode,local,nonlocal){
 assert.ok(["inside","outside"].includes(mode));
 assert.equal(local,"connected","LOOPBACK_PROBE_FAILED");
 if(mode==="outside")assert.equal(nonlocal,"connected","HOST_CANARY_UNREACHABLE");
 else assert.ok(["EACCES","EPERM"].includes(nonlocal),"NONLOOPBACK_NOT_DENIED");
 return {local:"connected",nonlocal:mode==="inside"?"denied":"connected"};
}
function connection(host,port){
 return new Promise(resolve=>{
  const socket=createConnection({host,port});
  let done=false;
  const finish=result=>{if(done)return;done=true;socket.destroy();resolve(result);};
  socket.setTimeout(1500);
  socket.once("connect",()=>finish("connected"));
  socket.once("timeout",()=>finish("timeout"));
  socket.once("error",error=>finish(error.code??"ERROR"));
 });
}
export async function probeWorkerBoundary(host,port,mode){
 assert.equal(isIP(host),4);
 assert.ok(!host.startsWith("127.")&&host!=="0.0.0.0","Require non-loopback host address");
 assert.ok(Object.values(networkInterfaces()).flat().some(item=>item&&!item.internal&&item.address===host),
  "Canary must target this host");
 assert.ok(Number.isSafeInteger(port)&&port>0&&port<=65535);
 return validateProbe(mode,await connection("127.0.0.1",port),await connection(host,port));
}
