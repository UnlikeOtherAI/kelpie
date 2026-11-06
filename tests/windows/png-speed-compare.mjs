import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {execFile} from "node:child_process";
import {readFile,writeFile} from "node:fs/promises";
import {promisify} from "node:util";
import {pathToFileURL} from "node:url";

const MAX_PNG=50_331_648, MAX_RGBA=33_554_432;
export function compareRgba(control,candidate){
 assert.ok(Buffer.isBuffer(control)&&Buffer.isBuffer(candidate));
 assert.ok(control.length>0&&control.length<=MAX_RGBA&&control.length%4===0);
 assert.equal(candidate.length,control.length);
 let transparent=0;for(let i=3;i<control.length;i+=4)if(control[i]!==255)transparent++;
 return {equal:control.equals(candidate),pixels:control.length/4,nonOpaquePixels:transparent,
  alphaCoverage:transparent?"nonopaque-observed":"opaque-only",rgbaSha256:createHash("sha256").update(control).digest("hex")};
}
export function checkPair(value){
 assert.equal(value.scope,"owned-frozen-fixture");assert.equal(value.format,"png");
 assert.deepEqual(value.options,{captureBeyondViewport:false});
 assert.match(value.binarySha256,/^[a-f0-9]{64}$/);
 assert.equal(value.control.binarySha256,value.binarySha256);assert.equal(value.candidate.binarySha256,value.binarySha256);
 assert.equal(value.control.optimizeForSpeed,false);assert.equal(value.candidate.optimizeForSpeed,true);
 assert.equal(value.control.fixtureId,value.candidate.fixtureId);assert.match(value.control.fixtureId,/^[a-f0-9]{32}$/);
}
async function main(){
 const [manifestFile,outputFile]=process.argv.slice(2);assert.ok(manifestFile&&outputFile&&process.env.FFMPEG);
 const manifest=JSON.parse(await readFile(manifestFile,"utf8"));checkPair(manifest);
 assert.match(manifest.ffmpegSha256,/^[a-f0-9]{64}$/);
 assert.equal(createHash("sha256").update(await readFile(manifest.binaryFile)).digest("hex"),manifest.binarySha256);
 assert.equal(createHash("sha256").update(await readFile(process.env.FFMPEG)).digest("hex"),manifest.ffmpegSha256);
 const exec=promisify(execFile),arms=[];
 for(const arm of [manifest.control,manifest.candidate]){
  const png=await readFile(arm.file);assert.ok(png.length>0&&png.length<=MAX_PNG);
  assert.ok(png.subarray(0,8).equals(Buffer.from("89504e470d0a1a0a","hex")));
  assert.ok(png.length>=24&&png.toString("ascii",12,16)==="IHDR");
  const width=png.readUInt32BE(16),height=png.readUInt32BE(20);
  assert.ok(width>0&&height>0&&width<=16384&&height<=16384&&width*height<=8388608);
  const sha256=createHash("sha256").update(png).digest("hex");assert.equal(sha256,arm.sha256);
  const result=await exec(process.env.FFMPEG,["-v","error","-i",arm.file,"-frames:v","1","-f","rawvideo","-pix_fmt","rgba","pipe:1"],
   {encoding:"buffer",maxBuffer:MAX_RGBA,timeout:30000,windowsHide:true});
  assert.equal(result.stdout.length,width*height*4);
  arms.push({sha256,bytes:png.length,width,height,rgba:result.stdout});
 }
 assert.equal(arms[0].width,arms[1].width);assert.equal(arms[0].height,arms[1].height);
 const comparison=compareRgba(arms[0].rgba,arms[1].rgba);
 await writeFile(outputFile,JSON.stringify({scope:manifest.scope,binarySha256:manifest.binarySha256,
  width:arms[0].width,height:arms[0].height,control:{sha256:arms[0].sha256,bytes:arms[0].bytes},candidate:{sha256:arms[1].sha256,bytes:arms[1].bytes},...comparison},null,2),{flag:"wx"});
 assert.equal(comparison.equal,true,"decoded RGBA mismatch");
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)await main();
