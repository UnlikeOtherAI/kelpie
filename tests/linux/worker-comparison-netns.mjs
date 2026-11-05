import assert from "node:assert/strict";
export function validateNetnsEvidence({host,unit,after,addresses,routes4,routes6}){
 assert.match(host,/^net:\[\d+\]$/);assert.match(unit,/^net:\[\d+\]$/);
 assert.equal(unit,after,"NETNS_CHANGED");assert.notEqual(unit,host,"NETNS_NOT_PRIVATE");
 assert.ok(Array.isArray(addresses)&&addresses.length===1,"NETNS_INTERFACE_COUNT");
 assert.equal(addresses[0].ifname,"lo","NETNS_NONLOOPBACK_INTERFACE");
 for(const [routes,family] of [[routes4,4],[routes6,6]]){
  assert.ok(Array.isArray(routes),"NETNS_ROUTES_INVALID");
  for(const route of routes){
   assert.equal(route.dev,"lo","NETNS_EXTERNAL_ROUTE");
   assert.ok(!route.gateway&&!route.nexthops&&!route.multipath,"NETNS_GATEWAY");
   assert.ok(typeof route.dst==="string"&&(family===4?/^127\./.test(route.dst):/^::1(?:\/128)?$/.test(route.dst)),"NETNS_NONLOOPBACK_ROUTE");
  }
 }
 return {distinctNamespace:true,interfaces:"loopback-only",externalRoutes:false};
}
