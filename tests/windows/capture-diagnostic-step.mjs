import {performance} from "node:perf_hooks";
const ALLOWED=new Set(["fixture-start","tabs","navigate","ready","workflow","events","artifact-download"]);
const KINDS=new Set(["AssertionError","Error","TypeError","AbortError","TimeoutError"]);
export async function captureDiagnosticStep(report,name,action){
 if(!ALLOWED.has(name))throw new Error("INVALID_DIAGNOSTIC_STEP");
 report.stage=name;
 const start=performance.now();
 try{
  const result=await action();
  report.steps.push({name,passed:true,elapsedMs:Math.round(performance.now()-start)});
  return result;
 }catch(error){
  report.steps.push({name,passed:false,elapsedMs:Math.round(performance.now()-start),
   kind:KINDS.has(error.name)?error.name:"Other"});
  throw error;
 }
}
