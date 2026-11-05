// Test-only independent decoding and identity receipt for the Linux GIF pointer model.
import assert from "node:assert/strict";
import { readFile, realpath, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { consumeG08Frames } from "../capture/g08-frame-stream.mjs";
import { resolve, join, dirname } from "node:path";

const [configPath, generatorPath, candidatePath, candidateEvidencePath, outputPath] = process.argv.slice(2);
assert.ok(outputPath, "Provide config, exact generator, candidate, independent candidate evidence and new output");
const hash = bytes => createHash("sha256").update(bytes).digest("hex");
const fileHash = async path => hash(await readFile(path));
const config = JSON.parse(await readFile(configPath, "utf8"));
const evidence = JSON.parse(await readFile(candidateEvidencePath, "utf8"));
const width = config.width, height = config.height, fps = config.fps, count = config.frameCount;
assert.ok(Number.isInteger(width) && width >= 2 && width <= 640);
assert.ok(Number.isInteger(height) && height >= 2 && height <= 1600);
assert.ok(Number.isInteger(fps) && fps >= 1 && fps <= 30);
assert.ok(Number.isInteger(count) && count >= 4 && count <= 60 && width * height * count <= 32000000);
assert.ok(Number.isInteger(config.viewportWidth) && Number.isInteger(config.viewportHeight));
const view = config.visualViewport, pointer = config.pointer;
assert.ok(view && pointer && [view.offsetLeft, view.offsetTop, view.width, view.height, view.scale,
  pointer.x, pointer.y].every(Number.isFinite));
assert.ok(view.width > 0 && view.height > 0 && view.scale > 0);
for (const name of ["LD_PRELOAD","LD_AUDIT","LD_LIBRARY_PATH"])
  assert.equal(process.env[name],undefined,"Model process has a loader override: "+name);
const candidateHash = await fileHash(candidatePath), generatorHash = await fileHash(generatorPath);
assert.equal(evidence.binarySHA256, candidateHash, "Observed app differs from requested candidate");
assert.equal(evidence.loaderOverridesAbsent,true);
assert.equal(await fileHash(candidateEvidencePath + ".maps.txt"),evidence.mapsSHA256);
assert.match(evidence.source, /^[a-f0-9]{40}$/);
const source = spawnSync("git", ["rev-parse", "HEAD"], {encoding:"utf8",timeout:5000});
assert.equal(source.status, 0);
const testSource = source.stdout.trim();
assert.match(testSource, /^[a-f0-9]{40}$/);
const unchanged = spawnSync("git", ["diff","--quiet",evidence.source,testSource,"--",
  "apps/linux/src","apps/linux/CMakeLists.txt","native","packages/shared","pnpm-lock.yaml"], {timeout:10000});
assert.equal(unchanged.status,0,"Candidate product inputs differ from model checkout");
const mediaObjects = join(dirname(resolve(generatorPath)), "CMakeFiles/kelpie_linux_script_media.dir/src");
const objectHashes = {
  compositor: await fileHash(join(mediaObjects, "script_frame_compositor.cpp.o")),
  gif: await fileHash(join(mediaObjects, "script_media_gif.cpp.o")),
  encoder: await fileHash(join(mediaObjects, "script_media_encoder.cpp.o")),
};
assert.deepEqual(evidence.mediaObjectSHA256, objectHashes, "Candidate build object identity differs");
const sourceHashes = {
  compositor: await fileHash("apps/linux/src/script_frame_compositor.cpp"),
  encoder: await fileHash("apps/linux/src/script_media_encoder.cpp"),
  gif: await fileHash("apps/linux/src/script_media_gif.cpp"),
};
assert.ok(Array.isArray(evidence.dependencies) && evidence.dependencies.length > 0);
for (const dependency of evidence.dependencies) {
  assert.ok(typeof dependency.path === "string" && dependency.path.startsWith("/"));
  assert.equal(await fileHash(dependency.path), dependency.sha256, "Observed dependency changed");
}
const buildRoot = dirname(resolve(generatorPath));
assert.equal(dirname(resolve(candidatePath)), buildRoot, "Candidate and generator must share a build directory");
const archive = join(buildRoot, "libkelpie_linux_script_media.a");
const maps = [join(buildRoot,"kelpie-linux-link.map"), join(buildRoot,"linux-script-gif-pointer-model-link.map")];
const members = {compositor:"script_frame_compositor.cpp.o",gif:"script_media_gif.cpp.o",encoder:"script_media_encoder.cpp.o"};
for (const [name, member] of Object.entries(members)) {
  const extracted = spawnSync("ar",["p",archive,member],{encoding:"buffer",timeout:10000,maxBuffer:20000000});
  assert.equal(extracted.status,0);
  assert.equal(hash(extracted.stdout),objectHashes[name],"Archive member differs from build object");
  for (const mapPath of maps) {
    const map = await readFile(mapPath,"utf8");
    assert.ok(map.includes("libkelpie_linux_script_media.a(" + member + ")"),"ELF link map omits media member");
  }
}
assert.equal(evidence.candidateLinkMapSHA256,await fileHash(maps[0]));
assert.equal(evidence.mediaArchiveSHA256,await fileHash(archive));
const output = resolve(outputPath);
const generated = spawnSync(resolve(generatorPath), [resolve(configPath), output],
  {encoding:"utf8",timeout:120000,maxBuffer:1048576});
assert.equal(generated.status, 0, generated.stderr || generated.stdout);
await writeFile(join(output,"generator-process.json"),JSON.stringify({pid:generated.pid,status:generated.status}),{flag:"wx"});
const generatedReport = JSON.parse(await readFile(join(output, "generator.json"), "utf8"));
assert.deepEqual(generatedReport.input, config);
assert.equal(generatedReport.encoder.palette, "RGB332-floor");
const mapped = new Set();
for (const line of (await readFile(join(output,"generator-maps.txt"),"utf8")).split("\n")) {
  const path = line.match(/\s(\/[^\n]+)$/)?.[1];
  if (path && /\/(?:libgif|libcairo|libpixman|libz\.so)/.test(path)) {
    assert.ok(!path.endsWith(" (deleted)")); mapped.add(await realpath(path));
  }
}
const generatorDependencies = [];
for (const path of [...mapped].sort()) generatorDependencies.push({path,sha256:await fileHash(path)});
const candidateMediaDependencies = evidence.dependencies.filter(item =>
  /\/(?:libgif\.so|libcairo\.so|libpixman|libz\.so)/.test(item.path));
const generatorMediaDependencies = generatorDependencies.filter(item =>
  /\/(?:libgif\.so|libcairo\.so|libpixman|libz\.so)/.test(item.path));
assert.deepEqual(generatorMediaDependencies,candidateMediaDependencies,
  "Live GIF/Cairo/Pixman/z dependencies differ from candidate");

const center = {x:(pointer.x-view.offsetLeft)*view.scale*width/config.viewportWidth,
  y:(pointer.y-view.offsetTop)*view.scale*height/config.viewportHeight};
const radius = 48*view.scale*width/config.viewportWidth;
const span = Math.ceil(radius*1.3+3);
const roi = {left:Math.max(0,Math.floor(center.x-span)),top:Math.max(0,Math.floor(center.y-span)),
  right:Math.min(width-1,Math.ceil(center.x+span)),bottom:Math.min(height-1,Math.ceil(center.y+span))};
assert.ok(roi.right >= roi.left && roi.bottom >= roi.top);
const entries = [];
for (const item of generatedReport.cases) {
  const path = resolve(item.file);
  assert.ok(path.startsWith(output + "/"), "Generator output escaped owned directory");
  const bytes = await readFile(path);
  assert.ok(bytes.length > 0 && bytes.length <= 33554432);
  const probe = spawnSync("ffprobe", ["-v","error","-select_streams","v:0","-show_frames",
    "-show_entries","frame=best_effort_timestamp_time:stream=width,height","-of","json",path],
    {encoding:"utf8",timeout:30000,maxBuffer:1048576});
  assert.equal(probe.status,0,probe.stderr);
  const info = JSON.parse(probe.stdout);
  assert.equal(info.streams[0].width,width); assert.equal(info.streams[0].height,height);
  const pts = info.frames.map(frame => Number(frame.best_effort_timestamp_time));
  assert.equal(pts.length,count);
  assert.ok(pts.every((v,i) => Number.isFinite(v) && (i===0 || v>pts[i-1])));
  const child = spawn("ffmpeg", ["-v","error","-threads","1","-filter_threads","1","-i",path,
    "-map","0:v:0","-vsync","0","-f","rawvideo","-pix_fmt","rgb24","-"],
    {stdio:["ignore","pipe","pipe"]});
  let stderr=""; child.stderr.on("data",chunk=>{if(stderr.length<4096)stderr+=chunk.toString().slice(0,4096-stderr.length);});
  const done=new Promise((ok,bad)=>{child.once("error",bad);child.once("close",code=>code===0?ok():bad(Error(stderr)));});
  void done.catch(()=>{});
  const timer=setTimeout(()=>child.kill(),120000), frames=[];
  const roiWidth=roi.right-roi.left+1, roiHeight=roi.bottom-roi.top+1;
  try {
    const decodedCount=await consumeG08Frames(child.stdout,width,height,(frame,index)=>{
      assert.ok(index<pts.length);
      const crop=Buffer.alloc(roiWidth*roiHeight*3);
      for(let y=roi.top;y<=roi.bottom;y++){
        const start=(y*width+roi.left)*3;
        frame.copy(crop,(y-roi.top)*roiWidth*3,start,start+roiWidth*3);
      }
      frames.push({index,ptsMs:pts[index]*1000,roiSHA256:hash(crop)});
    });
    await done;assert.equal(decodedCount,count);
  } finally {clearTimeout(timer);if(child.exitCode===null)child.kill();await done.catch(()=>{});}
  entries.push({name:item.name,marker:item.marker,file:path,sha256:hash(bytes),byteLength:bytes.length,frames});
}
assert.deepEqual(entries.map(item=>item.name),["pointer","small","faint","full","palette-collision"]);
const model = entries[0].frames[0].roiSHA256;
assert.ok(entries[0].frames.every(frame=>frame.roiSHA256===model),"Pointer model is unstable");
for (const item of entries.slice(1,4))
  assert.ok(item.frames.some(frame=>frame.roiSHA256!==model),"A retained-marker negative is invisible");
assert.ok(entries[4].frames.every(frame=>frame.roiSHA256===model),
  "Palette-collision control is distinguishable; no ambiguity claim can be made");
const report={version:1,confidence:"insufficient",provenance:"loader binding closure unverified",source:evidence.source,testSource,
  candidateBinarySHA256:candidateHash,generatorSHA256:generatorHash,generatorPID:generated.pid,
  candidateEvidenceSHA256:await fileHash(candidateEvidencePath),generatorMapsSHA256:await fileHash(join(output,"generator-maps.txt")),mediaObjectSHA256:objectHashes,mediaArchiveSHA256:await fileHash(archive),candidateLinkMapSHA256:await fileHash(maps[0]),generatorLinkMapSHA256:await fileHash(maps[1]),generatorDependencies,sourceSHA256:sourceHashes,input:config,
  encoder:generatedReport.encoder,roi,cases:entries};
await writeFile(join(output,"model-manifest.json"),JSON.stringify(report,null,2),{flag:"wx"});
console.log(JSON.stringify({output,modelROI:model,cases:entries.map(({name,sha256})=>({name,sha256}))}));
