import test from "node:test";
import assert from "node:assert/strict";
import {alphaControlWgcArgs} from "./wgc-alpha-control-args.mjs";
test("the exact process identity uses the native Windows executable path",()=>{
 assert.deepEqual(alphaControlWgcArgs({pid:42,startFileTime:"123",hwnd:"456"},"D:/owned/control.exe","D:/owned/capture"),
  ["42","D:\\owned\\control.exe","123","456","D:/owned/capture"]);
});
