import {test} from "node:test";
import assert from "node:assert/strict";
import {startSmokeFixture} from "./worker-comparison-smoke-fixture.mjs";
test("only the nonce-bound loopback canary admits the smoke",async()=>{
 const fixture=await startSmokeFixture("a".repeat(64));
 try{
  const page=await fetch(fixture.origin);assert.equal(page.status,200);
  assert.match(await page.text(),/fetch\("\/canary\//);
  assert.equal((await fetch(fixture.origin+"/canary/"+"b".repeat(64))).status,404);
  assert.equal(await fixture.waitForCanary(10),false);
  assert.equal((await fetch(fixture.origin+"/canary/"+"a".repeat(64))).status,204);
  assert.equal(await fixture.waitForCanary(50),true);
 }finally{await fixture.close();}
});
