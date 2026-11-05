import {parseWgcStages} from "./wgc-stage-timing.mjs";
const errors=new Set(["WGC_UNSUPPORTED","WGC_FRESH_DIRECTORY_REQUIRED","WGC_MEMORY_JOB_UNAVAILABLE","WGC_TIMELINE_PIXEL_BOUND","WGC_ANALYSIS_SIZE","WGC_BORDER_REQUIRED","WGC_ITEM_CLOSED","WGC_SIZE_CHANGED","WGC_CLOCK","WGC_ALPHA_MODE","WGC_ALPHA_MODE_CHANGED","WGC_ALPHA_MODE_INCONSISTENT","WGC_STREAM_FAILED","WGC_OUTPUT_BOUND","WGC_SESSION_DURATION_BOUND","WGC_DEADLINE","WGC_OPERATION_TIMEOUT","WGC_WINDOW_IDENTITY_MISMATCH","WGC_PROCESS_IDENTITY_MISMATCH","WGC_PROCESS_UNAVAILABLE","WGC_PROCESS_CHANGED","WGC_SESSION_MISMATCH"]);
export function safeWgcDiagnostic(stderr){
 const lines=String(stderr??"").split(/\r?\n/),result={stages:parseWgcStages(stderr),error:null,apiStage:null,apiCode:null};
 for(const line of lines){
  if(errors.has(line))result.error=line;
  const api=/^WGC_API_FAILURE stage=([a-z-]{1,64}) (-?\d{1,10})$/.exec(line);
  if(api){result.error="WGC_API_FAILURE";result.apiStage=api[1];result.apiCode=Number(api[2]);}
 }
 return result;
}
