import {test} from "node:test";
import assert from "node:assert/strict";
import {validateProbe,classifySocketError} from "./worker-comparison-network.mjs";
import {validateWorkerPolicy,verifyWorkerPolicyBinding,verifyWorkerObservationBinding} from "./worker-comparison-policy.mjs";
const good=["User=1001","ActiveState=active","ExecMainPID=123","NoNewPrivileges=yes",
 "KillMode=control-group","ControlGroup=/system.slice/kelpie-worker-ab-123-1-lightpanda.service","MemoryMax=2147483648","TasksMax=256","CPUQuotaPerSecUSec=1s",
 "IPAddressDeny=0.0.0.0/0 ::/0","IPAddressAllow=127.0.0.0/8 ::1/128"].join("\n");
test("independent unit policy rejects extra network grants and resource drift",()=>{
 assert.equal(validateWorkerPolicy(good,"1001").pid,123);
 for(const changed of [
  good.replace("User=1001","User=root"),good.replace("ExecMainPID=123","ExecMainPID=0"),
  good.replace("NoNewPrivileges=yes","NoNewPrivileges=no"),
  good.replace("KillMode=control-group","KillMode=process"),
  good.replace("ControlGroup=/system.slice/kelpie-worker-ab-123-1-lightpanda.service","ControlGroup=/other"),
  good.replace("MemoryMax=2147483648","MemoryMax=4294967296"),
  good.replace("IPAddressDeny=0.0.0.0/0 ::/0","IPAddressDeny="),
  good.replace("IPAddressAllow=127.0.0.0/8 ::1/128","IPAddressAllow=127.0.0.0/8 ::1/128 0.0.0.0/0"),
 ])assert.throws(()=>validateWorkerPolicy(changed,"1001"));
});
test("network probe requires a reachable control and explicit in-unit denial",()=>{
 assert.deepEqual(validateProbe("outside","connected","connected"),{local:"connected",nonlocal:"connected"});
 assert.deepEqual(validateProbe("inside","connected","EPERM"),{local:"connected",nonlocal:"denied"});
 assert.throws(()=>validateProbe("inside","connected","timeout"),/NONLOOPBACK_NOT_DENIED/);
 assert.throws(()=>validateProbe("inside","connected","ECONNREFUSED"),/NONLOOPBACK_NOT_DENIED/);
 assert.throws(()=>validateProbe("inside","timeout","EPERM"),/LOOPBACK_PROBE_FAILED/);
 assert.throws(()=>validateProbe("outside","connected","ECONNREFUSED"),/HOST_CANARY_UNREACHABLE/);
});

test("unit policy must bind to the observed benchmark process and denial",()=>{
 const policy=validateWorkerPolicy(good,"1001");
 const report={pid:123,uid:1001,networkProbe:{local:"connected",nonlocal:"denied"}};
 verifyWorkerPolicyBinding(policy,report,"1001");
 assert.throws(()=>verifyWorkerPolicyBinding(policy,{...report,pid:124},"1001"),/POLICY_PROCESS_MISMATCH/);
 assert.throws(()=>verifyWorkerPolicyBinding(policy,{...report,uid:0},"1001"),/POLICY_USER_MISMATCH/);
 assert.throws(()=>verifyWorkerPolicyBinding(policy,{...report,networkProbe:{local:"connected",nonlocal:"connected"}},"1001"));
});
test("raw connection classifications remain bounded and tied to the active process",()=>{
 for(const code of ["EACCES","EPERM","ECONNREFUSED","ECONNRESET","ENETUNREACH","EHOSTUNREACH","EADDRNOTAVAIL","ETIMEDOUT"]) assert.equal(classifySocketError(code),code);
 assert.equal(classifySocketError("sensitive unexpected text"),"OTHER");
 const policy=validateWorkerPolicy(good,"1001");
 const observation={pid:123,uid:1001,observed:{local:"connected",nonlocal:"timeout"}};
 assert.deepEqual(verifyWorkerObservationBinding(policy,observation,"1001"),observation.observed);
 assert.throws(()=>verifyWorkerObservationBinding(policy,{...observation,pid:124},"1001"));
 assert.throws(()=>verifyWorkerObservationBinding(policy,{...observation,uid:0},"1001"));
 assert.throws(()=>verifyWorkerObservationBinding(policy,{...observation,observed:{local:"connected",nonlocal:"raw message"}},"1001"));
});
