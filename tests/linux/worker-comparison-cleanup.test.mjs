import {test} from "node:test";
import assert from "node:assert/strict";
import {EventEmitter} from "node:events";
import {observeClientClose,clientCloseWasForced,observeEngineStop,engineStopFailure} from "./worker-comparison-cleanup.mjs";
function child(){
 const process=new EventEmitter();process.pid=42;process.exitCode=null;process.signalCode=null;
 process.kill=()=>true;return process;
}
test("client cleanup distinguishes clean EOF, SDK escalation, and timeout",async()=>{
 let process=child(),transport={_process:process,pid:42};
 let client={async close(){process.exitCode=0;process.emit("exit",0,null);}};
 let receipt=await observeClientClose(client,transport,{timeoutMs:30});
 assert.equal(receipt.status,"resolved");assert.equal(clientCloseWasForced(receipt),false);
 process=child();transport={_process:process,pid:42};
 client={async close(){process.kill("SIGTERM");process.exitCode=0;process.emit("exit",0,null);}};
 receipt=await observeClientClose(client,transport,{timeoutMs:30});
 assert.deepEqual(receipt.signals,["SIGTERM"]);assert.equal(clientCloseWasForced(receipt),true);
 process=child();transport={_process:process,pid:42};client={close:()=>new Promise(()=>{})};
 receipt=await observeClientClose(client,transport,{timeoutMs:5});
 assert.equal(receipt.status,"timeout");assert.equal(receipt.settled,false);assert.equal(clientCloseWasForced(receipt),true);
});
test("engine cleanup reports SIGTERM success and SIGKILL escalation separately",async()=>{
 let process=child();process.kill=signal=>{if(signal==="SIGTERM"){process.signalCode="SIGTERM";queueMicrotask(()=>process.emit("exit",null,"SIGTERM"));}return true;};
 let receipt=await observeEngineStop(process,{termMs:20,killMs:20});
 assert.equal(receipt.termWait,"resolved");assert.equal(receipt.killSent,false);
 process=child();process.kill=signal=>{if(signal==="SIGKILL"){process.signalCode="SIGKILL";queueMicrotask(()=>process.emit("exit",null,"SIGKILL"));}return true;};
 receipt=await observeEngineStop(process,{termMs:5,killMs:20});
 assert.equal(receipt.termWait,"timeout");assert.equal(receipt.killSent,true);assert.equal(receipt.killWait,"resolved");
});

test("unexpected engine termination or failed signal never qualifies as clean",()=>{
 const good={state:"running",termAccepted:true,termWait:"resolved",killSent:false,exitCode:0,exitSignal:null};
 assert.equal(engineStopFailure(good),null);
 assert.equal(engineStopFailure({...good,exitCode:null,exitSignal:"SIGTERM"}),null);
 for(const changed of [{state:"already-exited"},{termAccepted:false},{termWait:"timeout"},{killSent:true},{exitCode:1},{exitCode:null,exitSignal:"SIGSEGV"}])
  assert.ok(engineStopFailure({...good,...changed}));
});
