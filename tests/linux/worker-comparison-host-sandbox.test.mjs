import {test} from "node:test";
import assert from "node:assert/strict";
import {validateHostSnapshot,validHostSandboxHandoff,hostAuditCategory} from "./worker-comparison-host-sandbox.mjs";
const unit={pid:1,ppid:0,startTicks:"10",userNs:"user:[1]",pidNs:"pid:[1]"};
const browser={pid:2,ppid:1,startTicks:"20",userNs:"user:[1]",pidNs:"pid:[1]",filters:1,sandboxFlagsSafe:true};
const renderer={pid:3,ppid:2,startTicks:"30",userNs:"user:[2]",pidNs:"pid:[1]",filters:2,seccomp:2,sandboxFlagsSafe:true,renderer:true};
const snapshot=()=>new Map([[1,{...unit}],[2,{...browser}],[3,{...renderer}]]);
test("host proof binds the unit and browser and checks every stable renderer",()=>{
 const before=snapshot(),after=snapshot();
 assert.equal(validateHostSnapshot({unitPid:1,browserPid:2,startTicks:"20",before,after}).rendererCount,1);
 assert.throws(()=>validateHostSnapshot({unitPid:1,browserPid:2,startTicks:"21",before,after}));
 const shifted=snapshot();shifted.get(3).filters=3;
 assert.throws(()=>validateHostSnapshot({unitPid:1,browserPid:2,startTicks:"20",before,after:shifted}),/AUDIT_RACE/);
 after.get(3).startTicks="31";
 assert.throws(()=>validateHostSnapshot({unitPid:1,browserPid:2,startTicks:"20",before,after}),/AUDIT_RACE/);
 const wrong=snapshot();wrong.get(3).ppid=1;
 assert.throws(()=>validateHostSnapshot({unitPid:1,browserPid:2,startTicks:"20",before:wrong,after:wrong}));
});
test("host handoff rejects stale identity and malformed success",()=>{
 const evidence={ownedRenderer:true,chromiumFlagsSafe:true,rendererSeccomp:2,additionalSeccompFilter:true,rendererNamespaceSeparated:true,allOwnedRenderers:true,rendererCount:1};
 const result={ok:true,pid:2,startTicks:"20",unitPid:1,nonce:"n",evidence};
 assert.equal(validHostSandboxHandoff(result,2,"20",1,"n"),true);
 assert.equal(validHostSandboxHandoff(result,2,"21",1,"n"),false);
 assert.equal(validHostSandboxHandoff({...result,evidence:{allOwnedRenderers:true}},2,"20",1,"n"),false);
 assert.equal(validHostSandboxHandoff({...result,nonce:"old"},2,"20",1,"n"),false);
 assert.equal(hostAuditCategory(Error("AUDIT_RACE")),"process-race");
 assert.equal(hostAuditCategory(Error("AUDIT_UNREADABLE")),"proc-unreadable");
});
