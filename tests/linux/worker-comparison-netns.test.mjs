import {test} from "node:test";
import assert from "node:assert/strict";
import {validateNetnsEvidence} from "./worker-comparison-netns.mjs";
const good={host:"net:[1]",unit:"net:[2]",after:"net:[2]",
 queries:{address:"ok",routes4:"ok",routes6:"ok",pid:"ok"},
 addresses:[{ifname:"lo",flags:["UP","LOOPBACK"],addr_info:[
  {family:"inet",local:"127.0.0.1",prefixlen:8},{family:"inet6",local:"::1",prefixlen:128}]}],
 routes4:[{dst:"127.0.0.0/8",dev:"lo"}],routes6:[{dst:"::1",dev:"lo"}]};
test("namespace proof rejects host, query, address and route failures",()=>{
 assert.equal(validateNetnsEvidence(good).distinctNamespace,true);
 assert.doesNotThrow(()=>validateNetnsEvidence({...good,routes6:[...good.routes6,{dst:"ff00::/8",type:"multicast",dev:"lo"}]}));
 for(const change of [{unit:good.host,after:good.host},{after:"net:[3]"},
  {queries:{...good.queries,routes4:"failed"}},{queries:{...good.queries,pid:"failed"}},
  {addresses:[{...good.addresses[0],flags:["UP"]}]},
  {addresses:[{...good.addresses[0],addr_info:[{family:"inet",local:"127.0.0.1",prefixlen:7}]}]},
  {addresses:[{...good.addresses[0],addr_info:[...good.addresses[0].addr_info,{family:"inet",local:"10.0.0.1",prefixlen:8}]}]},
  {addresses:[...good.addresses,{ifname:"eth0"}]}, {routes4:[{dst:"default",dev:"lo"}]},
  {routes4:[{dst:"127.0.0.0/7",dev:"lo"}]}, {routes6:[{dst:"::/0",dev:"lo"}]},
  {routes6:[{dst:"ff00::/8",dev:"lo"}]}, {routes4:[{dst:"127.0.0.1",dev:"eth0"}]},
  {routes4:[{dst:"127.0.0.1",dev:"lo",gateway:"1.1.1.1"}]}])
  assert.throws(()=>validateNetnsEvidence({...good,...change}));
});
