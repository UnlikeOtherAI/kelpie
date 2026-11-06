import assert from "node:assert/strict";

// systemctl show is collected independently while the measured unit is active.
export function validateWorkerPolicy(text,expectedUser){
 const entries=new Map();
 for(const line of text.trim().split("\n")){
  const index=line.indexOf("=");assert.ok(index>0,"POLICY_INVALID");
  const key=line.slice(0,index);assert.ok(!entries.has(key),"POLICY_DUPLICATE");
  entries.set(key,line.slice(index+1).trim());
 }
 assert.ok(expectedUser&&expectedUser!=="root"&&expectedUser!=="0");
 assert.equal(entries.get("User"),expectedUser,"POLICY_USER");
 assert.equal(entries.get("ActiveState"),"active","POLICY_NOT_ACTIVE");
 assert.ok(Number(entries.get("ExecMainPID"))>0,"POLICY_NO_PROCESS");
 assert.equal(entries.get("NoNewPrivileges"),"yes","POLICY_NNP");
 assert.equal(entries.get("KillMode"),"control-group","POLICY_KILL_MODE");
 assert.equal(entries.get("PrivateNetwork"),"yes","POLICY_PRIVATE_NETWORK");
 assert.match(entries.get("ControlGroup")??"",
  /^\/system\.slice\/kelpie-worker-ab-\d+-\d+-(lightpanda|playwright|probe|sandbox|eof)\.service$/);
 assert.equal(entries.get("MemoryMax"),"2147483648","POLICY_MEMORY");
 assert.equal(entries.get("TasksMax"),"256","POLICY_TASKS");
 assert.ok(["1s","1000000us"].includes(entries.get("CPUQuotaPerSecUSec")),"POLICY_CPU");
 const denied=entries.get("IPAddressDeny")??"",allowed=entries.get("IPAddressAllow")??"";
 const denyParts=denied.split(/\s+/).filter(Boolean),allowParts=allowed.split(/\s+/).filter(Boolean);
 assert.ok(denied==="any"||(denyParts.length===2&&denyParts.includes("0.0.0.0/0")&&denyParts.includes("::/0")),"POLICY_DENY");
 assert.ok(allowed==="localhost"||(allowParts.length===2&&
  (allowParts.includes("127.0.0.0/8")||allowParts.includes("127.0.0.1/32"))&&
  allowParts.includes("::1/128")),"POLICY_ALLOW");
 return {pid:Number(entries.get("ExecMainPID")),active:true,nonRoot:true,cpu:1,memoryBytes:2147483648,tasks:256,network:"loopback-only",noNewPrivileges:true};
}

export function verifyWorkerPolicyBinding(policy,report,expectedUser){
 assert.equal(report.pid,policy.pid,"POLICY_PROCESS_MISMATCH");
 assert.equal(String(report.uid),expectedUser,"POLICY_USER_MISMATCH");
 assert.deepEqual(report.networkProbe,{local:"connected",nonlocal:"denied"});
}
export function verifyWorkerObservationBinding(policy,observation,expectedUser){
 assert.equal(observation.pid,policy.pid,"POLICY_PROCESS_MISMATCH");
 assert.equal(String(observation.uid),expectedUser,"POLICY_USER_MISMATCH");
 const values=["connected","timeout","EACCES","EPERM","ECONNREFUSED","ECONNRESET",
  "ENETUNREACH","EHOSTUNREACH","EADDRNOTAVAIL","ETIMEDOUT","OTHER"];
 assert.ok(values.includes(observation.observed?.local)&&values.includes(observation.observed?.nonlocal),
  "OBSERVATION_INVALID");
 return observation.observed;
}