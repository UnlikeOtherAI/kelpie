import assert from "node:assert/strict";
import {execFile} from "node:child_process";
import {promisify} from "node:util";
import test from "node:test";
const run=promisify(execFile);
for(const failure of ["invalid-json","disconnect"])test("early play "+failure+" preserves rejection and public cleanup",async()=>{
 const helper=new URL("./interactive-stop-lifecycle.mjs",import.meta.url).href;
 const code=`
 import http from "node:http";
 import {once} from "node:events";
 import {observeInFlight,awaitBounded} from ${JSON.stringify(helper)};
 let cleaned=false,rejected=false;
 const server=http.createServer((request,response)=>{
   if(request.url==="/stop"){cleaned=true;response.end("{}");return;}
   if(${JSON.stringify(failure)}==="disconnect"){request.socket.destroy();return;}
   response.writeHead(503,{"content-type":"application/json"});response.end("not-json");
 });
 server.listen(0,"127.0.0.1");await once(server,"listening");
 const base="http://127.0.0.1:"+server.address().port;
 const pending=observeInFlight(fetch(base+"/play").then(response=>response.json()));
 try {await new Promise(done=>setTimeout(done,60));await pending;}
 catch {rejected=true;}
 finally {await fetch(base+"/stop",{method:"POST"});server.close();server.closeAllConnections();await once(server,"close");}
 console.log(JSON.stringify({rejected,cleaned}));
 `;
 const result=await run(process.execPath,["--input-type=module","-e",code],{timeout:5000,windowsHide:true});
 assert.deepEqual(JSON.parse(result.stdout),{rejected:true,cleaned:true});
});

for(const result of ["resolve","reject"])test("cleanup timeout retires after early "+result,async()=>{
 const helper=new URL("./interactive-stop-lifecycle.mjs",import.meta.url).href;
 const code=`import {awaitBounded} from ${JSON.stringify(helper)};
 try {await awaitBounded(Promise.${result}(${result==="resolve"?'"ok"':'new Error("expected")'}),30000);}catch{}
 console.log("retired");`;
 const child=await run(process.execPath,["--input-type=module","-e",code],{timeout:2000,windowsHide:true});
 assert.equal(child.stdout.trim(),"retired");
});
