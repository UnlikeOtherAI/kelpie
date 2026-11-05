import assert from "node:assert/strict";
import {writeFile} from "node:fs/promises";
import {resolve} from "node:path";
import {snapshotNativeResources} from "./native-resource-snapshot.mjs";

// Test-only, point-in-time observations; never record request URLs or messages.
export function createNavigationResourceDiagnostic({pid,startTicks,output,snapshot=snapshotNativeResources,sink=writeFile}) {
  assert.ok(Number.isSafeInteger(pid)&&pid>1&&/^\d+$/.test(startTicks??""));
  let sequence=0, truncated=false; const snapshots=[];
  async function sample(index) {
    try { return await snapshot({pid,startTicks,sequence:index}); }
    catch { return {pid,startTicks,sequence:index,identityValid:false,complete:false}; }
  }
  return {
    async invoke(method,request) {
      if(method!=="navigate") return request();
      const index=sequence++;
      if(index>=512) { truncated=true; return request(); }
      const before=await sample(index); let value;
      try { value=await request(); return value; }
      finally {
        const after=await sample(index);
        const message=typeof value?.error?.message==="string"?value.error.message:"";
        snapshots.push({sequence:index,before,after,responseSuccess:value?.success===true?1:value?0:-1,
          navigationError:value?.error?.code==="NAVIGATION_ERROR"?1:0,
          insufficientResources:message.includes("ERR_INSUFFICIENT_RESOURCES")?1:0});
      }
    },
    async write() {
      await sink(resolve(output,"resource-diagnostics.json"),
        JSON.stringify({version:1,instrumented:true,truncated,snapshots},null,2),{flag:"wx"});
    },
  };
}
