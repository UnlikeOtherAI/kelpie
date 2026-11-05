import assert from "node:assert/strict";
import {isIP} from "node:net";
function loopback4(cidr){
 if(typeof cidr!=="string")return false;
 const parts=cidr.split("/");
 if(parts.length>2||isIP(parts[0])!==4||!parts[0].startsWith("127."))return false;
 return parts.length===1||(/^\d+$/.test(parts[1])&&Number(parts[1])>=8&&Number(parts[1])<=32);
}
export function validateNetnsEvidence({host,unit,after,addresses,routes4,routes6,queries}){
 assert.match(host,/^net:\[\d+\]$/);assert.match(unit,/^net:\[\d+\]$/);
 assert.equal(unit,after,"NETNS_CHANGED");assert.notEqual(unit,host,"NETNS_NOT_PRIVATE");
 assert.deepEqual(queries,{address:"ok",routes4:"ok",routes6:"ok",pid:"ok"},"NETNS_QUERY_FAILED");
 assert.ok(Array.isArray(addresses)&&addresses.length===1,"NETNS_INTERFACE_COUNT");
 const lo=addresses[0];
 assert.equal(lo.ifname,"lo","NETNS_NONLOOPBACK_INTERFACE");
 assert.ok(Array.isArray(lo.flags)&&lo.flags.includes("LOOPBACK"),"NETNS_LOOPBACK_FLAG");
 assert.ok(Array.isArray(lo.addr_info)&&lo.addr_info.length>0,"NETNS_ADDRESSES");
 let ipv4=false,ipv6=false;
 for(const addr of lo.addr_info){
  if(addr.family==="inet"&&loopback4(addr.local+"/"+addr.prefixlen))ipv4=true;
  else if(addr.family==="inet6"&&addr.local==="::1"&&addr.prefixlen===128)ipv6=true;
  else assert.fail("NETNS_NONLOOPBACK_ADDRESS");
 }
 assert.ok(ipv4&&ipv6,"NETNS_LOOPBACK_FAMILIES");
 for(const [routes,family] of [[routes4,4],[routes6,6]]){
  assert.ok(Array.isArray(routes),"NETNS_ROUTES_INVALID");
  for(const route of routes){
   assert.equal(route.dev,"lo","NETNS_EXTERNAL_ROUTE");
   assert.ok(!route.gateway&&!route.nexthops&&!route.multipath,"NETNS_GATEWAY");
   const loopback=family===4?loopback4(route.dst):/^::1(?:\/128)?$/.test(route.dst??"");
   const localMulticast=family===6&&route.dst==="ff00::/8"&&route.type==="multicast";
   assert.ok(loopback||localMulticast,"NETNS_NONLOOPBACK_ROUTE");
  }
 }
 return {distinctNamespace:true,interfaces:"loopback-only",externalRoutes:false};
}
