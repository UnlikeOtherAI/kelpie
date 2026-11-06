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
