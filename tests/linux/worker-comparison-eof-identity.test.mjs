import {test} from "node:test";
import assert from "node:assert/strict";
import {fixtureIdentity,fixtureWasDisposed} from "./worker-comparison-eof-identity.mjs";
const url="http://127.0.0.1/owned-fixture";
const target={type:"page",url,targetId:"owned",browserContextId:"context"};
test("binds a unique fixture and requires both target and context disposal",()=>{
 const id=fixtureIdentity([target],url);
 assert.equal(fixtureWasDisposed([{targetId:"other",browserContextId:"default"}],["default"],id),true);
 assert.equal(fixtureWasDisposed([target],[],id),false);
 assert.equal(fixtureWasDisposed([],["context"],id),false);
 assert.equal(fixtureWasDisposed([{targetId:"other",browserContextId:"context"}],[],id),false);
});
test("fails closed for ambiguous or missing target and context facts",()=>{
 assert.throws(()=>fixtureIdentity([],url));
 assert.throws(()=>fixtureIdentity([target,target],url));
 assert.throws(()=>fixtureIdentity([{...target,browserContextId:undefined}],url));
 assert.throws(()=>fixtureWasDisposed([],null,{targetId:"owned",browserContextId:"context"}));
});
