import {listenerState} from "./runtime-ownership.mjs";

// Read-only confirmation only. Never retry a renderer switch or other mutation.
export async function waitForRendererTransition({pid,probe,verifyReveal,readEngine,noteFailure,lastFailure,recordEngine,delay,now},engine,timeoutMs=30000){
 const deadline=now()+timeoutMs;
 const inspect=()=>{
  const value=probe(),state=listenerState(value.owners,pid);
  if(state==="owned"&&value.outcome==="success")return "owned";
  if(state==="missing"&&value.outcome==="no-match"&&!value.stderrPresent)return "missing";
  noteFailure(value);
  throw Object.assign(new Error("LISTENER_IDENTITY"),{code:"LISTENER_IDENTITY"});
 };
 while(now()<deadline){
  if(inspect()==="missing"){
   await verifyReveal();
   await delay(100);
   continue;
  }
  try{
   const value=await readEngine();
   if(["webkit","chromium"].includes(value.engine))recordEngine(value.engine);
   if(value.engine===engine)return value;
  }catch(error){
   if(error?.code==="LISTENER_IDENTITY"){
    const previous=lastFailure();
    if(previous?.port!=="api"||previous.state!=="missing"||previous.probeOutcome!=="no-match"||previous.probeStderrPresent)throw error;
   }
   // A read may be interrupted by the known transient; verify that exact state before waiting.
   if(inspect()!=="missing")throw error;
   await verifyReveal();
  }
  await delay(100);
 }
 throw Object.assign(new Error("WAIT_TIMEOUT"),{code:"WAIT_TIMEOUT"});
}
