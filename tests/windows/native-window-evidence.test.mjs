import assert from "node:assert/strict";
import test from "node:test";
import {nativeMarkerVerified} from "./native-window-evidence.mjs";
test("native window red text and Stop-only images cannot certify a marker",()=>{
 assert.equal(nativeMarkerVerified([
  {className:"Kelpie",status:"pixels-captured",redPixels:365},
  {className:"KelpieScriptStop",status:"pixels-captured",redPixels:9},
  {className:"KelpieScriptPresentation",status:"layer-transparency-or-black-background-unsupported",redPixels:326}
 ]),false);
});
test("marker evidence requires connected pixels at the expected center and radius",()=>{
 const image={className:"KelpieScriptPresentation",status:"pixels-captured",
  markerRegion:{verified:true,minimumPixels:450,connectedPixels:1200,centerWithinExpected:true,radiusWithinExpected:true}};
 assert.equal(nativeMarkerVerified([image]),true);
 for(const change of [{connectedPixels:365},{centerWithinExpected:false},{radiusWithinExpected:false},{minimumPixels:0}]){
  assert.equal(nativeMarkerVerified([{...image,markerRegion:{...image.markerRegion,...change}}]),false);
 }
});
