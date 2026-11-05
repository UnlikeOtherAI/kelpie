import {test} from "node:test";
import assert from "node:assert/strict";
import {g08NativeGeometry} from "./g08-native-geometry.mjs";

function fixture(top=62,bottom=34){
  const visualViewport={offsetLeft:0,offsetTop:0,width:402,height:874-top-bottom,scale:1};
  const event=(target,x,y)=>({target,documentId:"1700000000000-abc",center:{x,y},visualViewport});
  return {artifact:{width:804,height:1748,documentId:"native",timestamps:[0,1],geometry:{
    kind:"constant-native-content",nativeDocumentId:"native",fixtureDocumentId:"1700000000000-abc",
    stableNativeDocument:true,observedFrames:3,encodedFrames:2,nativeBounds:{width:402,height:874},
    contentRect:{x:0,y:top,width:402,height:874-top-bottom},visualViewport}},
  scene:{warmup:event("finish",175,340),calibration:event("finish",175,340),
    start:event("start",75,340),finish:event("finish",175,340)}};
}
test("same-scene iPhone top inset maps CSS to native and encoded coordinates",()=>{
  const {artifact,scene}=fixture();const g=g08NativeGeometry(artifact,scene);
  assert.deepEqual(g.to,{x:175,y:402});assert.deepEqual(g.scale,{x:2,y:2});
  assert.equal(g.to.y*g.scale.y,804);
});
test("zero top inset preserves native coordinates",()=>{
  const {artifact,scene}=fixture(0,20);assert.deepEqual(g08NativeGeometry(artifact,scene).to,{x:175,y:340});
});
test("missing, mismatched or unstable per-artifact mapping is insufficient",()=>{
  for(const change of [
    f=>delete f.artifact.geometry,
    f=>delete f.scene.warmup,
    f=>f.scene.calibration.documentId="1700000000000-def",
    f=>f.artifact.geometry.encodedFrames--,
    f=>f.artifact.geometry.observedFrames=1,
    f=>f.artifact.geometry.observedFrames=2.5,
    f=>f.artifact.documentId="other",
    f=>f.artifact.geometry.stableNativeDocument=false,
    f=>f.artifact.geometry.fixtureDocumentId="other",
    f=>f.artifact.geometry.fixtureDocumentId="1700000000000-ABC",
    f=>f.artifact.geometry.nativeDocumentId="",
    f=>f.scene.finish.visualViewport={...f.scene.finish.visualViewport,offsetTop:1},
    f=>f.artifact.geometry.contentRect.y=900,
    f=>f.artifact.geometry.contentRect.width-=10,
  ]){const f=fixture();change(f);assert.throws(()=>g08NativeGeometry(f.artifact,f.scene));}
});

test("same-scene iPad mapping and nonzero visual origin",()=>{
  const {artifact,scene}=fixture(0,20);
  const g=artifact.geometry;
  g.nativeBounds={width:1024,height:1366};
  g.contentRect={x:0,y:0,width:1024,height:1346};
  g.visualViewport={offsetLeft:0,offsetTop:0,width:1024,height:1346,scale:1};
  artifact.width=1024;artifact.height=1366;
  for(const event of Object.values(scene))event.visualViewport=g.visualViewport;
  assert.deepEqual(g08NativeGeometry(artifact,scene).to,{x:175,y:340});
  g.visualViewport={...g.visualViewport,offsetTop:20};
  for(const event of Object.values(scene))event.visualViewport=g.visualViewport;
  assert.deepEqual(g08NativeGeometry(artifact,scene).to,{x:175,y:320});
});