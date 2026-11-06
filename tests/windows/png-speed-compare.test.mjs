import {test} from "node:test";
import assert from "node:assert/strict";
import {checkPair,compareRgba} from "./png-speed-compare.mjs";
test("requires matching binary and exact frozen PNG option contract",()=>{
 const hash="a".repeat(64),id="b".repeat(32);
 const pair={scope:"owned-frozen-fixture",format:"png",options:{captureBeyondViewport:false},binarySha256:hash,
  control:{binarySha256:hash,fixtureId:id,optimizeForSpeed:false},candidate:{binarySha256:hash,fixtureId:id,optimizeForSpeed:true}};
 assert.doesNotThrow(()=>checkPair(pair));assert.throws(()=>checkPair({...pair,candidate:{...pair.candidate,binarySha256:"c".repeat(64)}}));
 assert.throws(()=>checkPair({...pair,options:{captureBeyondViewport:true}}));
});
test("compares every RGBA byte and labels opaque-only input truthfully",()=>{
 assert.equal(compareRgba(Buffer.from([1,2,3,255]),Buffer.from([1,2,3,255])).alphaCoverage,"opaque-only");
 assert.equal(compareRgba(Buffer.from([1,2,3,20]),Buffer.from([1,2,3,20])).nonOpaquePixels,1);
 assert.equal(compareRgba(Buffer.from([1,2,3,20]),Buffer.from([1,2,3,21])).equal,false);
 assert.throws(()=>compareRgba(Buffer.alloc(4),Buffer.alloc(8)));
});
