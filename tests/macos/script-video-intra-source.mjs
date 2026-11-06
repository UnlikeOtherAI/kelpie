import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {execFileSync} from "node:child_process";
import {readFile,writeFile} from "node:fs/promises";
import path from "node:path";
import {pathToFileURL} from "node:url";

const anchor="            AVVideoAllowFrameReorderingKey: false,\n";
const addition="            AVVideoMaxKeyFrameIntervalKey: 1,\n";
export function intraWriterSource(source){
 assert.equal(typeof source,"string");
 assert.equal(source.split(anchor).length,2,"INTRA_SOURCE_ANCHOR");
 assert.ok(!source.includes("AVVideoMaxKeyFrameIntervalKey:"),"INTRA_SOURCE_ALREADY_MODIFIED");
 return source.replace(anchor,anchor+addition);
}

if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
 const [output,metadata]=process.argv.slice(2);assert.ok(output&&metadata&&process.argv.length===4,"INTRA_ARGUMENTS");
 const file="apps/macos/Kelpie/Handlers/ScriptVideoWriter.swift",original=await readFile(file);
 const tracked=execFileSync("git",["show","HEAD:"+file],{maxBuffer:1048576});
 assert.ok(original.equals(tracked),"INTRA_SOURCE_NOT_TRACKED");
 const transformed=Buffer.from(intraWriterSource(original.toString("utf8")));
 assert.ok(transformed.length===original.length+Buffer.byteLength(addition),"INTRA_SOURCE_SIZE");
 const digest=bytes=>createHash("sha256").update(bytes).digest("hex");
 const receipt={version:1,source:file,sourceSHA256:digest(original),transformedSHA256:digest(transformed),
  insertion:"AVVideoMaxKeyFrameIntervalKey: 1"};
 await writeFile(output,transformed,{flag:"wx"});
 await writeFile(metadata,JSON.stringify(receipt,null,2)+"\n",{flag:"wx"});
}
