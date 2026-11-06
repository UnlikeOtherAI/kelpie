import {runLightpandaReaderDiagnostics} from "./lightpanda-reader-diagnostics.mjs";

const allowed=new Set(["SESSION_CLOSED","SESSION_NOT_FOUND","TAB_NOT_FOUND","WORKER_FAILED","ACCESS_DENIED","UNSUPPORTED","INVALID_ARGUMENTS","RESOURCE_LIMIT"]);
const stop=Symbol("diagnostic stop");

// Report only fixed stages, categories, and monotonic durations; never raw page or error data.
export async function diagnoseChromiumFirstFailure({call,origin,now,sessionStarted,timeoutError}){
 const receipt={scope:"cold-navigation-and-readers",stages:[],firstFailure:null,complete:false};
 const stage=async(name,method,params,validate=()=>null,expectedRefusal=null)=>{
  const start=now(),age=Math.max(0,start-sessionStarted);
  let category="ok",result;
  try{
   result=await call(method,params);
   if(!result||typeof result!=="object"||typeof result.ok!=="boolean")category="malformed_envelope";
   else if(!result.ok){const code=result.error?.code;category=expectedRefusal&&code===expectedRefusal?"ok":typeof code!=="string"||!code?"malformed_envelope":allowed.has(code)?"public_"+code:"public_other";}
   else if(Object.hasOwn(result,"error"))category="malformed_envelope";
   else if(expectedRefusal)category="expected_refusal_missing";
   else category=validate(result)??"ok";
  }catch(error){category=error===timeoutError?"public_timeout":error instanceof SyntaxError?"malformed_envelope":"transport_failed";}
  const end=now();receipt.stages.push({stage:name,category,startMs:Math.max(0,start-sessionStarted),
   durationMs:Math.max(0,end-start),sessionAgeUpperBoundMs:age,ttlRemainingLowerBoundMs:Math.max(0,60000-age)});
  if(category!=="ok"){receipt.firstFailure={stage:name,category};throw stop;}
  return result;
 };
 const expectOk=()=>null, title=expected=>r=>typeof r.value!=="string"?"malformed_envelope":r.value===expected?null:"title_mismatch",
  url=expected=>r=>typeof r.value!=="string"?"malformed_envelope":r.value===expected?null:"url_mismatch";
 try{
  await stage("second-session-refused","__session_limit",{},()=>null,"RESOURCE_LIMIT");
  await stage("tabs-list","tabs.list",{},r=>!Array.isArray(r.value)?"malformed_envelope":r.value.length===1?null:"tab_count_mismatch");
  await stage("goto-root","tab.goto",{url:origin},expectOk);
  await stage("title-root","tab.title",{},title("Worker fixture"));
  await stage("url-root","tab.url",{},url(origin+"/"));
  await stage("goto-next","tab.goto",{url:origin+"/next"},expectOk);
  await stage("back","tab.back",{},expectOk);
  await stage("url-back","tab.url",{},url(origin+"/"));
  await stage("forward","tab.forward",{},expectOk);
  await stage("title-next","tab.title",{},title("Next fixture"));
  await stage("reload","tab.reload",{},expectOk);
  await stage("goto-reader","tab.goto",{url:origin+"/readers"},expectOk);
  await runLightpandaReaderDiagnostics({
   check:async(name,fn)=>{
    const start=now(),age=Math.max(0,start-sessionStarted);
    try{await fn();return true;}catch(error){
     if(error===stop)throw stop;
     const referenceCategories={REFERENCE_FORMAT_INVALID:"reference_format",REFERENCE_DUPLICATE:"reference_duplicate",
      REFERENCE_GENERATION_MIXED:"reference_generation_mixed",REFERENCE_GENERATION_REUSED:"reference_generation_reused"};
     const category=Object.hasOwn(referenceCategories,error?.message)?referenceCategories[error.message]:"assertion_other";
     receipt.stages.push({stage:name,category,startMs:age,durationMs:Math.max(0,now()-start),
      sessionAgeUpperBoundMs:age,ttlRemainingLowerBoundMs:Math.max(0,60000-age)});
     receipt.firstFailure={stage:name,category};throw stop;
    }
   },
   selected:["snapshot","extract","status","ready"],adversariesInstalled:()=>true,referencePrefix:()=>"e",referenceMode:"managed",
   read:async(kind,options={})=>{
    const params={...options};delete params.prefix;
    return (await stage("reader-"+kind,"tab."+kind,params)).value;
   },
  });
  receipt.complete=true;
 }catch(error){if(error!==stop)throw error;}
 return receipt;
}
