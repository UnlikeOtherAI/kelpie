import assert from "node:assert/strict";

const [input,output,...extra]=process.argv.slice(2);
assert.ok(input&&output&&extra.length===0,"Provide one case input and a fresh output");
process.argv=[process.argv[0],process.argv[1],input,output,undefined,undefined,undefined,"--single-case"];
await import("./g08-verify.mjs");
