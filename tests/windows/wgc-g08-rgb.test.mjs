import test from "node:test";import assert from "node:assert/strict";
import {whiteBackedRGB} from "./wgc-g08-rgb.mjs";
test("white-backed analysis preserves alpha semantics without changing input",()=>{
 const straight=Buffer.from([0,0,255,128,0,0,0,0,0,0,0,255]),before=Buffer.from(straight);
 assert.deepEqual([...whiteBackedRGB(straight,3,1,"straight")],[255,127,127,255,255,255,0,0,0]);assert.deepEqual(straight,before);
 const premult=Buffer.from([0,0,128,128]);assert.deepEqual([...whiteBackedRGB(premult,1,1,"premultiplied")],[255,127,127]);
 assert.throws(()=>whiteBackedRGB(Buffer.from([0,0,240,128]),1,1,"premultiplied"),/INVALID_PREMULTIPLIED/);
 assert.throws(()=>whiteBackedRGB(Buffer.alloc(4),1,1,"ignore"));
 assert.throws(()=>whiteBackedRGB(Buffer.alloc(3),1,1,"straight"));
});
