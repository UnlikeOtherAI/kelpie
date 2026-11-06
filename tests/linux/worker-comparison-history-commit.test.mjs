import {test} from "node:test";
import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {readFile} from "node:fs/promises";
import {transformHistoryBuild} from "./worker-comparison-history-commit.mjs";
const source="fixed adapter source\n",sha=createHash("sha256").update(source).digest("hex");
const back='await page.goBack({ waitUntil: "domcontentloaded", timeout });';
const forward='await page.goForward({ waitUntil: "domcontentloaded", timeout });';
const chunks=text=>[{name:"chunk.js",text}];
test("patches only one back wait and reports both hashes",()=>{
 const out=transformHistoryBuild(source,chunks(back+"\n"+forward),sha);
 assert.ok(out.result.includes('await page.goBack({ waitUntil: "commit", timeout });'));
 assert.ok(out.result.includes(forward));assert.notEqual(out.receipt.beforeSha256,out.receipt.afterSha256);
});
test("rejects source drift, absent or duplicate back, and changed forward",()=>{
 assert.throws(()=>transformHistoryBuild("other",chunks(back+"\n"+forward),sha));
 assert.throws(()=>transformHistoryBuild(source,chunks(forward),sha));
 assert.throws(()=>transformHistoryBuild(source,chunks(back+"\n"+back+"\n"+forward),sha));
 assert.throws(()=>transformHistoryBuild(source,chunks(back),sha));
 assert.throws(()=>transformHistoryBuild(source,[{name:"a",text:back+"\n"+forward},{name:"b",text:back}],sha));
});
test("the exact checked-in adapter matches the experiment pin",async()=>{
 const actual=await readFile(new URL("../../packages/shared/src/browser-control/playwright.ts",import.meta.url),"utf8");
 assert.equal(transformHistoryBuild(actual,chunks(back+"\n"+forward)).receipt.changed,"tab.back-only");
});
