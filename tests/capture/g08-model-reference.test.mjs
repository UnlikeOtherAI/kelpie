import test from "node:test";
import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {validateG08ModelFacts,validateG08ObservedRows} from "./g08-model-reference.mjs";
const hash=value=>createHash("sha256").update(value).digest("hex");
function fixture(){
 const white=hash(Buffer.alloc(71*71*4,255)), pointer="1".repeat(64);
 const view={offsetLeft:0,offsetTop:0,width:1280,height:900,scale:1};
 const frames=(roiSHA256)=>Array.from({length:30},(_,index)=>({index,ptsMs:index*50,roiSHA256}));
 const item={runId:"owned",capture:{fps:20},scene:{finish:{center:{x:960,y:450},viewport:{width:1280,height:900},visualViewport:view}}};
 const artifact={mimeType:"image/gif",partial:false,width:640,height:450,sha256:"gif",documentId:"doc"};
 const dependencies=["libgif.so","libcairo.so","libpixman.so","libz.so"].map(path=>({path:"/lib/"+path,sha256:path}));
 const evidence={source:"source",binarySHA256:"binary",loaderOverridesAbsent:true,dependencies,mediaObjectSHA256:{gif:"object"},
  mediaArchiveSHA256:"archive",candidateLinkMapSHA256:"link"};
 const manifest={version:1,source:"source",candidateBinarySHA256:"binary",candidateEvidenceSHA256:"evidence",
  mediaObjectSHA256:{gif:"object"},mediaArchiveSHA256:"archive",candidateLinkMapSHA256:"link",generatorDependencies:dependencies,
  encoder:{mimeType:"image/gif",palette:"RGB332-floor",sourcePixelFormat:"BGRA8-opaque"},
  input:{width:640,height:450,fps:20,frameCount:30,viewportWidth:1280,viewportHeight:900,visualViewport:view,pointer:{x:960,y:450}},
  roi:{left:445,top:190,right:515,bottom:260},cases:[
   {name:"pointer",marker:null,frames:frames(pointer)},
   ...["small","faint","full"].map((name,i)=>({name,marker:{color:"#0000FF",radiusCss:i===0?4:48,ageMs:[0,650,0][i],durationMs:700,fade:true,wobble:false,baseAlpha:178/255},frames:frames(String(i+2).repeat(64))})),
   {name:"palette-collision",marker:{color:"#0000FF",radiusCss:48,ageMs:699,durationMs:700,fade:true,wobble:false,baseAlpha:178/255},frames:frames(pointer)}]};
 const actualPTS=[0,.05,.1];
 const backing={version:1,confidence:"test-only-backing-observed",source:"source",binarySHA256:"binary",
  candidateEvidenceSHA256:"evidence",captureReportSHA256:"input",gifSHA256:"gif",run:"owned",documentId:"doc",
  roi:[445,190,71,71],bgraSHA256:white,frameCount:3,
  frames:actualPTS.map((pts,i)=>({sequence:i,ptsMs:pts*1000,bgraSHA256:white}))};
 return {input:{runtime:"linux-gtk-cef",source:"source",binarySHA256:"binary"},inputSHA256:"input",
  item,artifact,actualPTS,manifest,backing,evidence,evidenceSHA256:"evidence"};
}
test("observed GIF model binds exact source, frame mapping and controls",()=>{
 assert.equal(validateG08ModelFacts(fixture()).roiHash,"1".repeat(64));
});
for(const [name,change] of [
 ["MP4",f=>f.artifact.mimeType="video/mp4"],["other platform",f=>f.input.runtime="windows-cef"],
 ["candidate",f=>f.evidence.binarySHA256="other"],["objects",f=>f.evidence.mediaObjectSHA256.gif="other"],
 ["capture hash",f=>f.backing.captureReportSHA256="other"],["artifact",f=>f.backing.gifSHA256="other"],
 ["run",f=>f.backing.run="other"],["document",f=>f.backing.documentId="other"],
 ["geometry",f=>f.item.scene.finish.center.x++],["ROI edge",f=>f.backing.roi[2]--],
 ["backing",f=>f.backing.frames[1].bgraSHA256="other"],["missing frame",f=>f.backing.frames.pop()],
 ["PTS",f=>f.backing.frames[1].ptsMs++],["unstable pointer",f=>f.manifest.cases[0].frames[1].roiSHA256="other"],
 ["small retained",f=>f.manifest.cases[1].frames[0].roiSHA256="1".repeat(64)],
 ["faint retained",f=>f.manifest.cases[2].frames[0].roiSHA256="1".repeat(64)],
 ["full retained",f=>f.manifest.cases[3].frames[0].roiSHA256="1".repeat(64)],
 ["collision",f=>f.manifest.cases[4].frames[0].roiSHA256="other"],
 ["expired collision",f=>f.manifest.cases[4].marker.ageMs=700],["wrong marker",f=>f.manifest.cases[1].marker.radiusCss=8],["missing view",f=>f.item.scene.finish.visualViewport=null],
]){
 test("model refuses "+name,()=>{const f=fixture();change(f);assert.throws(()=>validateG08ModelFacts(f),/INSUFFICIENT_EVIDENCE/);});
}

test("observed backing requires every exact white frame and matching timestamp",()=>{
 const f=fixture(),white=Buffer.alloc(71*71*4,255),evidence={pid:42};
 const rows=f.actualPTS.map((time,i)=>({pid:42,run:"owned",documentId:"doc",sequence:i,
   frameWidth:640,frameHeight:450,stride:2560,sourceWidth:1280,sourceHeight:900,viewportWidth:1280,viewportHeight:900,
   visualViewport:f.item.scene.finish.visualViewport,roi:[445,190,71,71],
   bgraBase64:white.toString("base64"),bgraSHA256:hash(white),elapsedMs:100+time*1000}));
 const backing={frames:rows.map(row=>({elapsedMs:row.elapsedMs}))};
 validateG08ObservedRows(rows,f,evidence,backing);
 for(const mutate of [
  r=>r.pop(),r=>r[1].elapsedMs++,r=>r[1].pid++,r=>r[1].documentId="wrong",
  r=>r[1].bgraBase64=Buffer.alloc(71*71*4,254).toString("base64"),
  r=>r[1].roi[2]--
 ]){const changed=structuredClone(rows);mutate(changed);assert.throws(()=>validateG08ObservedRows(changed,f,evidence,backing),/INSUFFICIENT_EVIDENCE/);}
});