import {test} from "node:test";
import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {allowedPaths,decodePinnedPatch,verifyPatchPaths,verifyStatusPaths,verifyFileHashes} from "./verify-history-patch.mjs";
test("accepts only bounded canonical base64 with the pinned digest",()=>{
 const bytes=Buffer.from("reviewed patch"),encoded=bytes.toString("base64"),sha=createHash("sha256").update(bytes).digest("hex");
 assert.deepEqual(decodePinnedPatch(encoded,sha),bytes);
 for(const invalid of [encoded+"!",encoded+"\n","A".repeat(24001),""])assert.throws(()=>decodePinnedPatch(invalid,sha));
 assert.throws(()=>decodePinnedPatch(encoded,"0".repeat(64)));
});
test("rejects extra, missing, duplicate and malformed paths",()=>{
 const output=allowedPaths.map(path=>"1\t1\t"+path).join("\n");verifyPatchPaths(output);
 assert.throws(()=>verifyPatchPaths(output+"\n1\t1\tother"));
 assert.throws(()=>verifyPatchPaths(allowedPaths.slice(1).map(path=>"1\t1\t"+path).join("\n")));
 assert.throws(()=>verifyPatchPaths(allowedPaths.map(()=> "1\t1\t"+allowedPaths[0]).join("\n")));
 assert.throws(()=>verifyPatchPaths(output.replace("1\t1\t","-\t-\t")));
});
test("all five resulting file hashes must match",()=>{
 const expected=Object.fromEntries(allowedPaths.map(path=>[path,"a".repeat(64)]));
 verifyFileHashes({...expected},expected);
 assert.throws(()=>verifyFileHashes({...expected,[allowedPaths[0]]:"b".repeat(64)},expected));
 assert.throws(()=>verifyFileHashes({...expected,extra:"x"},expected));
});

test("status parsing preserves the first modified-file leading space",()=>{
 const output=allowedPaths.map((path,index)=>(index<3?" M ":"?? ")+path).join("\n")+"\n";
 verifyStatusPaths(output);
 assert.throws(()=>verifyStatusPaths(output.replace(" M ","R  ")));
});