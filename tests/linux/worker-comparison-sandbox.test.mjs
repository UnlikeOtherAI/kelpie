import {test} from "node:test";
import assert from "node:assert/strict";
import {validateSandboxFacts,parseStatusValue} from "./worker-comparison-sandbox.mjs";
const browser={owned:true,sandboxFlagsSafe:true,filters:1,userNs:"user:[1]",pidNs:"pid:[1]"};
const renderer={owned:true,descendant:true,sandboxFlagsSafe:true,seccomp:2,filters:2,userNs:"user:[2]",pidNs:"pid:[1]"};
test("sandbox proof needs owned renderer, new seccomp filter and separate namespace",()=>{
 assert.equal(validateSandboxFacts(browser,renderer).ownedRenderer,true);
 for(const change of [{owned:false},{descendant:false},{sandboxFlagsSafe:false},{seccomp:0},
  {filters:1},{userNs:"user:[1]"},{filters:null}])
  assert.throws(()=>validateSandboxFacts(browser,{...renderer,...change}));
 assert.throws(()=>validateSandboxFacts({...browser,sandboxFlagsSafe:false},renderer));
});

test("proc status parsing rejects absent or malformed filter evidence",()=>{
 assert.equal(parseStatusValue("Seccomp:\t2\nSeccomp_filters:\t4\n","Seccomp"),2);
 assert.equal(parseStatusValue("Seccomp_filters:\t4\n","Seccomp_filters"),4);
 assert.equal(parseStatusValue("Seccomp: yes","Seccomp"),null);
});
