import {isDeepStrictEqual} from "node:util";
const hex=(value,length)=>typeof value==="string"&&new RegExp("^[a-f0-9]{"+length+"}$").test(value);
export function comparisonReason(reports){
 if(reports.length!==4||reports.some(x=>x.status.code!==0||x.status.signal||!x.report?.focusedScopePassed||!x.report?.ownedChildExited||!x.report?.ownedListenersReleased))return "ARM_FAILED";
 const first=reports[0].report;
 if(reports.some(({report:r})=>!hex(r.source,40)||![r.executableHash,r.debugLibraryHash,r.cefFrameworkHash].every(x=>hex(x,64))||r.source!==first.source||r.executableHash!==first.executableHash||r.debugLibraryHash!==first.debugLibraryHash||r.cefFrameworkHash!==first.cefFrameworkHash))return "BINARY_MISMATCH";
 const extract=arm=>arm.report.engines?.find(x=>x.engine==="chromium")?.checks?.filter(x=>x.name.startsWith("png-equivalence-")).map(x=>x.detail);
 const baseline=extract(reports[0]);
 if(!baseline||baseline.length!==3||baseline.map(x=>x.name).join(",")!=="static,noisy,layered"||baseline.some(x=>!hex(x.rgbaSHA256,64)))return "PIXEL_MISSING";
 if(new Set(baseline.map(x=>x.rgbaSHA256)).size!==3)return "FIXTURE_NOT_DISTINCT";
 if(baseline.some(x=>!isDeepStrictEqual(x.viewport,baseline[0].viewport)))return "VIEWPORT_MISMATCH";
 const comparable=x=>({name:x.name,width:x.width,height:x.height,hash:x.rgbaSHA256,alpha:x.alpha,viewport:x.viewport,pattern:x.pattern});
 if(reports.some(arm=>{const facts=extract(arm);return !facts||facts.length!==3||facts.some((x,i)=>!isDeepStrictEqual(comparable(x),comparable(baseline[i])));}))return "PIXEL_MISMATCH";
 return null;
}

const phases=new Set(["launch","listeners","pairing","chromium","cleanup"]);
const checks=new Set(["native-renderer-control","strict-capability","public-navigation-from-start-page","png-equivalence-static","png-equivalence-noisy","png-equivalence-layered"]);
const stages=new Set(["navigation","identity-before","viewport-before","screenshot","viewport-after","identity-after","download","decode","pattern","cleanup"]);
const codes=new Set(["FIXTURE_NAVIGATION","LISTENER_IDENTITY","PIXEL_WINDOW","PIXEL_WINDOW_CHANGED","PIXEL_RENDERER_VIEWPORT","PIXEL_RENDERER_VIEWPORT_CHANGED","PIXEL_WORKFLOW","PIXEL_ARTIFACT","PIXEL_SIZE","PIXEL_LENGTH","PIXEL_FIXTURE_MISSING","RESPONSE_LIMIT","CHUNK_IDENTITY","CHUNK_OFFSET","CHUNK_EOF","ARTIFACT_HASH","ARTIFACT_LIMIT","CAPTURE_PIXEL_SOURCE_UNAVAILABLE","CAPTURE_DOCUMENT_CHANGED","CAPTURE_VIEWPORT_CHANGED","CAPTURE_DURATION_LIMIT","CAPTURE_BYTE_LIMIT","CAPTURE_STOPPED","UNAUTHORIZED","SCRIPT_ABORTED","PNG_MODE_UNCONFIRMED","HOSTED_RUNTIME_FAILED","FOCUSED_RENDERER","NATIVE_MORE_MISSING","PUBLIC_NAVIGATION","STRICT_CAPABILITY_MISSING","WAIT_TIMEOUT","OWNED_CHILD_TEARDOWN_TIMEOUT"]);
export function safeArmFailures(report){
 if(!report)return {phase:"unavailable",failure:"unavailable",checks:[]};
 const phase=phases.has(report.phaseAtFailure)?report.phaseAtFailure:report.phaseAtFailure?"other":"none";
 const failures=(report.engines??[]).flatMap(engine=>engine.checks??[]).filter(item=>item.passed===false).slice(0,8).map(item=>({check:checks.has(item.name)?item.name:"other",stage:stages.has(item.pixelStage)?item.pixelStage:"other",code:codes.has(item.code)?item.code:"OTHER"}));
 return {phase,failure:report.failure?(codes.has(report.failure)?report.failure:"OTHER"):"none",checks:failures};
}
