// Test-harness observations of the pinned SDK child and owned engine.
import {performance} from "node:perf_hooks";

function within(promise,ms){
 let timer;
 return Promise.race([
  Promise.resolve(promise).then(()=> "resolved",()=> "rejected"),
  new Promise(ok=>{timer=setTimeout(()=>ok("timeout"),ms);}),
 ]).finally(()=>clearTimeout(timer));
}
export async function observeClientClose(client,transport,{timeoutMs=2000}={}){
 const child=transport?._process,pid=transport?.pid;
 const receipt={status:"not-started",elapsedMs:0,visibility:"unavailable",pid:null,signals:[],
  exitObserved:false,exitCode:null,exitSignal:null,settled:false};
 if(child&&Number.isSafeInteger(pid)&&pid>0&&child.pid===pid&&typeof child.kill==="function"){
  receipt.visibility="owned-handle";receipt.pid=pid;
  const kill=child.kill;
  child.kill=function(signal,...args){
   receipt.signals.push(signal==="SIGTERM"||signal==="SIGKILL"?signal:"OTHER");
   return kill.call(this,signal,...args);
  };
  const exited=(code,signal)=>{receipt.exitObserved=true;receipt.exitCode=code;receipt.exitSignal=signal;};
  child.once("exit",exited);
  if(child.exitCode!==null||child.signalCode!==null)exited(child.exitCode,child.signalCode);
 }
 const begin=performance.now();
 const closing=Promise.resolve().then(()=>client.close());
 closing.then(()=>{receipt.settled=true;},()=>{receipt.settled=true;});
 receipt.status=await within(closing,timeoutMs);receipt.elapsedMs=performance.now()-begin;
 return receipt;
}
export function clientCloseWasForced(receipt){
 return receipt.visibility!=="owned-handle"||receipt.status!=="resolved"||!receipt.exitObserved||
  receipt.signals.length>0||receipt.exitCode!==0||receipt.exitSignal!==null;
}
export async function observeEngineStop(engine,{termMs=1500,killMs=1500}={}){
 const receipt={state:engine?"already-exited":"absent",termSent:false,termAccepted:null,
  termWait:"not-started",killSent:false,killAccepted:null,killWait:"not-started",
  exitCode:null,exitSignal:null,elapsedMs:0};
 if(!engine)return receipt;
 const begin=performance.now();
 if(engine.exitCode===null&&engine.signalCode===null){
  receipt.state="running";
  const exited=new Promise(ok=>engine.once("exit",ok));
  receipt.termSent=true;
  try{receipt.termAccepted=engine.kill("SIGTERM");}catch{receipt.termAccepted=false;}
  receipt.termWait=await within(exited,termMs);
  if(receipt.termWait==="timeout"&&engine.exitCode===null&&engine.signalCode===null){
   receipt.killSent=true;
   try{receipt.killAccepted=engine.kill("SIGKILL");}catch{receipt.killAccepted=false;}
   receipt.killWait=await within(exited,killMs);
  }
 }
 receipt.exitCode=engine.exitCode;receipt.exitSignal=engine.signalCode;
 receipt.elapsedMs=performance.now()-begin;return receipt;
}

export function engineStopFailure(receipt){
 if(receipt.state!=="running")return "unexpected-exit";
 if(receipt.termAccepted!==true)return "term-failed";
 if(receipt.termWait!=="resolved"||receipt.killSent)return "term-timeout";
 if(!((receipt.exitCode===0&&receipt.exitSignal===null)||(receipt.exitCode===null&&receipt.exitSignal==="SIGTERM")))return "unexpected-status";
 return null;
}
