import {test} from "node:test";
import assert from "node:assert/strict";
import {validateNetnsEvidence} from "./worker-comparison-netns.mjs";
const good={host:"net:[1]",unit:"net:[2]",after:"net:[2]",addresses:[{ifname:"lo"}],routes4:[{dst:"127.0.0.0/8",dev:"lo"}],routes6:[{dst:"::1",dev:"lo"}]};
test("namespace proof rejects host, interface, route and identity drift",()=>{
 assert.equal(validateNetnsEvidence(good).distinctNamespace,true);
 for(const change of [{unit:good.host,after:good.host},{after:"net:[3]"},
  {addresses:[{ifname:"lo"},{ifname:"eth0"}]}, {routes4:[{dst:"default",dev:"lo"}]},
  {routes6:[{dst:"::/0",dev:"lo"}]}, {routes4:[{dst:"127.0.0.1",dev:"eth0"}]},
  {routes4:[{dst:"127.0.0.1",dev:"lo",gateway:"1.1.1.1"}]}])
  assert.throws(()=>validateNetnsEvidence({...good,...change}));
});
