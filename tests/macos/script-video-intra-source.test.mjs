import test from "node:test";
import assert from "node:assert/strict";
import {execFileSync} from "node:child_process";
import {intraWriterSource} from "./script-video-intra-source.mjs";
test("only one exact test-only keyframe setting is inserted",()=>{
 const input="begin\n            AVVideoAllowFrameReorderingKey: false,\nend\n";
 assert.equal(intraWriterSource(input),"begin\n            AVVideoAllowFrameReorderingKey: false,\n            AVVideoMaxKeyFrameIntervalKey: 1,\nend\n");
 assert.throws(()=>intraWriterSource("no anchor"),/INTRA_SOURCE_ANCHOR/);
 assert.throws(()=>intraWriterSource(input+input),/INTRA_SOURCE_ANCHOR/);
 assert.throws(()=>intraWriterSource(input+"AVVideoMaxKeyFrameIntervalKey: 2"),/INTRA_SOURCE_ALREADY_MODIFIED/);
});

test("tracked writer has exactly the reviewed insertion point",()=>{
 const source=execFileSync("git",["show","HEAD:apps/macos/Kelpie/Handlers/ScriptVideoWriter.swift"],{encoding:"utf8"});
 const updated=intraWriterSource(source);
 assert.equal(updated.replace("            AVVideoMaxKeyFrameIntervalKey: 1,\n",""),source);
});
