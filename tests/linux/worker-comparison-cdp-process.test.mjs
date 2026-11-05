import {test} from "node:test";
import assert from "node:assert/strict";
import {parseDevToolsActivePort,extractRendererPids,performProcessQuery} from "./worker-comparison-cdp-process.mjs";
test("DevTools endpoint is bounded and constrained to the browser target",()=>{
 assert.equal(parseDevToolsActivePort("1234\n/devtools/browser/01234567-89ab-cdef-0123-456789abcdef\n").port,1234);
 for(const bad of ["0\n/devtools/browser/01234567-89ab-cdef-0123-456789abcdef","1234\n/devtools/page/anything","1234\nhttp://external"])
  assert.throws(()=>parseDevToolsActivePort(bad));
});
test("DevTools process list requires exact browser identity and unique renderer PIDs",()=>{
 const response={result:{processInfo:[{type:"browser",id:2},{type:"renderer",id:4},{type:"renderer",id:3}]}};
 assert.deepEqual(extractRendererPids(response,2),[3,4]);
 assert.throws(()=>extractRendererPids(response,7));
 assert.throws(()=>extractRendererPids({result:{processInfo:[{type:"browser",id:2}]}},2));
 assert.throws(()=>extractRendererPids({result:{processInfo:[{type:"browser",id:2},{type:"renderer",id:3},{type:"renderer",id:3}]}},2));
});

test("browser protocol query sends only process-info and accepts its matching response",async()=>{
 const handlers={};let sent=null,closed=false;
 const socket={addEventListener(name,fn){handlers[name]=fn;},
  send(value){sent=JSON.parse(value);queueMicrotask(()=>handlers.message({data:JSON.stringify({id:1,result:{processInfo:[{type:"browser",id:2},{type:"renderer",id:3}]}})}));},
  close(){closed=true;}};
 const result=performProcessQuery(socket,2);handlers.open();
 assert.deepEqual(await result,[3]);assert.deepEqual(sent,{id:1,method:"SystemInfo.getProcessInfo"});assert.equal(closed,true);
});