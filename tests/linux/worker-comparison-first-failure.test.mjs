import {test} from "node:test";
import assert from "node:assert/strict";
import {diagnoseChromiumFirstFailure} from "./worker-comparison-first-failure.mjs";
async function sample(result,error){
 let calls=0,clock=0;const timeoutError=Error("deadline");
 const receipt=await diagnoseChromiumFirstFailure({origin:"http://fixture",sessionStarted:0,now:()=>clock+=10,timeoutError,
  call:async(method)=>{if(method==="__session_limit")return {ok:false,error:{code:"RESOURCE_LIMIT"}};calls++;if(error==="timeout")throw timeoutError;if(error==="transport")throw Error("private");
   return result;}});
 return {receipt,calls};
}
test("safe error categories and malformed envelopes are bounded",async()=>{
 for(const [value,category] of [[{ok:false,error:{code:"SESSION_CLOSED"}},"public_SESSION_CLOSED"],
  [{ok:false,error:{code:"PRIVATE_SECRET"}},"public_other"],[{ok:"true"},"malformed_envelope"]]){
  const {receipt,calls}=await sample(value);assert.equal(calls,1);assert.equal(receipt.firstFailure.category,category);
  assert.ok(!JSON.stringify(receipt).includes("PRIVATE_SECRET"));
 }
});
test("timeout, transport, count mismatch and TTL are distinguished",async()=>{
 assert.equal((await sample(null,"timeout")).receipt.firstFailure.category,"public_timeout");
 assert.equal((await sample(null,"transport")).receipt.firstFailure.category,"transport_failed");
 const value=await sample({ok:true,value:[]});assert.equal(value.receipt.firstFailure.category,"tab_count_mismatch");
 assert.equal(value.receipt.stages[1].ttlRemainingLowerBoundMs,59970);
});
test("a mismatch stops before any further call",async()=>{
 let n=0;const values=[{ok:true,value:[{}]},{ok:true},{ok:true,value:"not fixture"}];
 const r=await diagnoseChromiumFirstFailure({origin:"http://fixture",now:()=>0,sessionStarted:0,timeoutError:Error("t"),
  call:async(method)=>method==="__session_limit"?{ok:false,error:{code:"RESOURCE_LIMIT"}}:values[n++]});
 assert.equal(r.firstFailure.stage,"title-root");assert.equal(r.firstFailure.category,"title_mismatch");assert.equal(n,3);
});

test("URL mismatch and expired TTL are reported without page values",async()=>{
 let n=0;const values=[{ok:true,value:[{}]},{ok:true},{ok:true,value:"Worker fixture"},{ok:true,value:"http://private"}];
 const receipt=await diagnoseChromiumFirstFailure({origin:"http://fixture",now:()=>65000,sessionStarted:0,timeoutError:Error("t"),
  call:async(method)=>method==="__session_limit"?{ok:false,error:{code:"RESOURCE_LIMIT"}}:values[n++]});
 assert.equal(receipt.firstFailure.category,"url_mismatch");assert.equal(receipt.stages.at(-1).ttlRemainingLowerBoundMs,0);
 assert.equal(n,4);assert.ok(!JSON.stringify(receipt).includes("http://private"));
});
test("missing error codes are malformed rather than trusted public errors",async()=>{
 assert.equal((await sample({ok:false,error:{}})).receipt.firstFailure.category,"malformed_envelope");
});
test("contradictory success and malformed tab lists are rejected",async()=>{
 assert.equal((await sample({ok:true,error:null})).receipt.firstFailure.category,"malformed_envelope");
 assert.equal((await sample({ok:true,value:null})).receipt.firstFailure.category,"malformed_envelope");
});
test("diagnostic reports fixed reference-format category without exposing refs",async()=>{
 let titleCalls=0;const call=async(method)=>{
  if(method==="__session_limit")return {ok:false,error:{code:"RESOURCE_LIMIT"}};
  if(method==="tabs.list")return {ok:true,value:[{}]};
  if(method==="tab.title")return {ok:true,value:titleCalls++===0?"Worker fixture":"Next fixture"};
  if(method==="tab.url")return {ok:true,value:"http://fixture/"};
  if(method==="tab.snapshot")return {ok:true,value:{elements:[{ref:"e1",name:"public"}],text:"public",truncated:true}};
  return {ok:true,value:null};
 };
 const r=await diagnoseChromiumFirstFailure({call,origin:"http://fixture",now:()=>0,sessionStarted:0,timeoutError:Error("t")});
 assert.equal(r.firstFailure.category,"reference_format");assert.ok(!JSON.stringify(r).includes("e1"));
});