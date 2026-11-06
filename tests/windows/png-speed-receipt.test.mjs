import {test} from "node:test";
import assert from "node:assert/strict";
import {parsePngSpeedBytes} from "./png-speed-receipt.mjs";
test("accepts bounded numeric receipts and rejects malformed or inconsistent facts",()=>{
 assert.deepEqual(parsePngSpeedBytes("KELPIE_TEST_SCRIPT_PNG_BYTES 2 300 200"),{count:2,totalBase64Chars:300,maxBase64Chars:200});
 assert.equal(parsePngSpeedBytes("KELPIE_TEST_SCRIPT_PNG_BYTES 0 1 1"),null);
 assert.equal(parsePngSpeedBytes("KELPIE_TEST_SCRIPT_PNG_BYTES 801 1 1"),null);
 assert.equal(parsePngSpeedBytes("KELPIE_TEST_SCRIPT_PNG_BYTES 1 10 11"),null);
 assert.equal(parsePngSpeedBytes("KELPIE_TEST_SCRIPT_PNG_BYTES 1 1 1 secret"),null);
});
