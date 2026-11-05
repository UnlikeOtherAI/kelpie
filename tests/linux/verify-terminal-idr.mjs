// Independent final AVC packet verification for a known terminal-clear fixture.
import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {readFile,writeFile} from "node:fs/promises";
import {spawnSync} from "node:child_process";
const [input,output]=process.argv.slice(2);assert.ok(input&&output);
const report=JSON.parse(await readFile(input,"utf8")),results=[];
const probe=(file,args)=>{
 const result=spawnSync("ffprobe",["-v","error","-select_streams","v:0",...args,"-of","json",file],{timeout:30000,maxBuffer:1048576});
 assert.equal(result.status,0,result.stderr?.toString()??result.error?.message);return JSON.parse(result.stdout);
};
for(const item of report.artifacts.filter(a=>a.mimeType==="video/mp4")) {
 const bytes=await readFile(item.file),sha=createHash("sha256").update(bytes).digest("hex");
 assert.equal(sha,item.sha256);
 const packets=probe(item.file,["-show_packets","-show_entries","packet=pos,size,flags,pts_time"]).packets;
 assert.equal(packets.length,item.frameCount);
 const last=packets.at(-1),pos=Number(last.pos),size=Number(last.size),pts=Number(last.pts_time);
 assert.ok(Number.isSafeInteger(pos)&&Number.isSafeInteger(size)&&pos>=0&&size>0&&pos+size<=bytes.length);
 assert.ok(Number.isFinite(pts)&&last.flags.includes("K"));
 const streams=probe(item.file,["-show_entries","stream=extradata","-show_data"]).streams;assert.equal(streams.length,1);
 const hex=streams[0].extradata.trim().split("\n").map(line=>line.split(":")[1].split("  ")[0].replace(/\s/g,"")).join("");
 assert.match(hex,/^(?:[0-9a-fA-F]{2})+$/);const config=Buffer.from(hex,"hex");assert.ok(config.length>=5&&config[0]===1);
 const lengthSize=(config[4]&3)+1,data=bytes.subarray(pos,pos+size);let offset=0,idr=false;
 while(offset<data.length) {
  assert.ok(offset+lengthSize<=data.length);
  const length=data.readUIntBE(offset,lengthSize);offset+=lengthSize;
  assert.ok(length>0&&offset+length<=data.length);
  if((data[offset]&31)===5)idr=true;
  offset+=length;
 }
 assert.ok(idr,"terminal packet lacks AVC IDR");
 results.push({id:item.id,sha256:sha,frames:packets.length,finalPTS:pts,packetSize:size,nalLengthSize:lengthSize,idr:true});
}
assert.ok(results.length>0);
await writeFile(output,JSON.stringify({source:report.source,results},null,2)+"\n",{flag:"wx"});
