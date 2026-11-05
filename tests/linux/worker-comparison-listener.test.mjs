import {test} from "node:test";
import assert from "node:assert/strict";
import {loopbackListenerInodes} from "./worker-comparison-listener.mjs";

test("only exact IPv4 loopback listener and port qualify",()=>{
 const header="sl local_address rem_address st tx rx tr uid timeout inode";
 const table=[header,
  "0: 0100007F:20E4 00000000:0000 0A 0 0 0 1000 0 12345",
  "1: 00000000:20E4 00000000:0000 0A 0 0 0 1000 0 99999",
  "2: 0100007F:20E4 00000000:0000 01 0 0 0 1000 0 88888",
  "3: 0100007F:20E5 00000000:0000 0A 0 0 0 1000 0 77777"].join("\n");
 assert.deepEqual([...loopbackListenerInodes(table,8420)],["12345"]);
 assert.equal(loopbackListenerInodes(table,8422).size,0);
 assert.throws(()=>loopbackListenerInodes(table,0));
});
