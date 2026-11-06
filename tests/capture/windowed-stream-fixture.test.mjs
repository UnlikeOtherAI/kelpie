import test from "node:test";
import assert from "node:assert/strict";
import {startWindowedStreamFixture} from "./windowed-stream-fixture.mjs";

test("nonce-bound fixture has distinct animated and static pages",async()=>{
 const fixture=await startWindowedStreamFixture();
 try{
  assert.match(fixture.nonce,/^[a-f0-9]{32}$/);
  const animated=await fetch(fixture.animated),stationary=await fetch(fixture.static);
  assert.equal(animated.status,200);assert.equal(stationary.status,200);
  const moving=await animated.text(),still=await stationary.text();
  assert.match(moving,/animation:move 2s linear infinite alternate/);
  assert.doesNotMatch(still,/animation:move 2s linear infinite alternate/);
  assert.equal((await fetch(`${fixture.origin}/other/animated`)).status,404);
  assert.equal((await fetch(`${fixture.static}?extra=1`)).status,404);
 }finally{await fixture.close();}
});
