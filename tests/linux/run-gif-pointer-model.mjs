// Test-only independent decoding and identity receipt for the Linux GIF pointer model.
import assert from "node:assert/strict";
import { readFile, stat, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
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
const candidateHash = await fileHash(candidatePath), generatorHash = await fileHash(generatorPath);
assert.equal(evidence.binarySHA256, candidateHash, "Observed app differs from requested candidate");
assert.match(evidence.source, /^[a-f0-9]{40}$/);
const source = spawnSync("git", ["rev-parse", "HEAD"], {encoding:"utf8",timeout:5000});
assert.equal(source.status, 0); assert.equal(source.stdout.trim(), evidence.source);
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
const output = resolve(outputPath);
const generated = spawnSync(resolve(generatorPath), [resolve(configPath), output],
  {encoding:"utf8",timeout:120000,maxBuffer:1048576});
assert.equal(generated.status, 0, generated.stderr || generated.stdout);
const generatedReport = JSON.parse(await readFile(join(output, "generator.json"), "utf8"));
assert.deepEqual(generatedReport.input, config);
assert.equal(generatedReport.encoder.palette, "RGB332-floor");
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
  const decoded = spawnSync("ffmpeg", ["-v","error","-threads","1","-filter_threads","1","-i",path,
    "-map","0:v:0","-fps_mode","passthrough","-f","rawvideo","-pix_fmt","rgb24","-"],
    {encoding:"buffer",timeout:120000,maxBuffer:100000000});
  assert.equal(decoded.status,0,decoded.stderr.toString());
  assert.equal(decoded.stdout.length,width*height*3*count);
  const frameBytes=width*height*3, roiWidth=roi.right-roi.left+1, roiHeight=roi.bottom-roi.top+1;
  const frames=pts.map((seconds,index) => {
    const crop=Buffer.alloc(roiWidth*roiHeight*3);
    for(let y=roi.top;y<=roi.bottom;y++){
      const start=index*frameBytes+(y*width+roi.left)*3;
      decoded.stdout.copy(crop,(y-roi.top)*roiWidth*3,start,start+roiWidth*3);
    }
    return {index,ptsMs:seconds*1000,roiSHA256:hash(crop)};
  });
  entries.push({name:item.name,marker:item.marker,file:path,sha256:hash(bytes),byteLength:bytes.length,frames});
}
assert.deepEqual(entries.map(item=>item.name),["pointer","small","faint","full","palette-collision"]);
const model = entries[0].frames[0].roiSHA256;
assert.ok(entries[0].frames.every(frame=>frame.roiSHA256===model),"Pointer model is unstable");
for (const item of entries.slice(1,4))
  assert.ok(item.frames.some(frame=>frame.roiSHA256!==model),"A retained-marker negative is invisible");
const report={version:1,confidence:"encoded-visible-only",source:evidence.source,
  candidateBinarySHA256:candidateHash,generatorSHA256:generatorHash,
  candidateEvidenceSHA256:await fileHash(candidateEvidencePath),mediaObjectSHA256:objectHashes,sourceSHA256:sourceHashes,input:config,
  encoder:generatedReport.encoder,roi,cases:entries};
await writeFile(join(output,"model-manifest.json"),JSON.stringify(report,null,2),{flag:"wx"});
console.log(JSON.stringify({output,modelROI:model,cases:entries.map(({name,sha256})=>({name,sha256}))}));
