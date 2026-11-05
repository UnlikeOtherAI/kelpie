import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {consumeWgcFrames} from "./wgc-frame-stream.mjs";
import {whiteBackedRGB} from "./wgc-g08-rgb.mjs";
import {measureG08Frame} from "../capture/g08-pixels.mjs";
import {evaluateG08} from "../capture/g08-timeline.mjs";
import {createG08Retention} from "./wgc-g08-retention.mjs";
// No caller-provided analysis is accepted. Provenance must be verified by the
// orchestration layer before any cross-stream comparison.
export async function evaluateWgcFrames(stream,config,{onProgress}={}){
 assert.ok(config&&["c","s"].includes(config.curve));
 assert.ok(Number.isFinite(config.viewport?.width)&&config.viewport.width>0&&Number.isFinite(config.viewport?.height)&&config.viewport.height>0);
 const retention=createG08Retention({warmupCalibration:true,pointerMs:config.pointerMs,markerMs:config.markerMs}),samples=retention.samples;let origin,shape;
 const count=await consumeWgcFrames(stream,(bgra,meta)=>{
  if(origin===undefined)origin=meta.tick100ns;
  const dimensions=meta.width+":"+meta.height;
  if(shape)assert.equal(dimensions,shape,"WGC_SIZE_CHANGED");else shape=dimensions;
  const scale={x:meta.width/config.viewport.width,y:meta.height/config.viewport.height};
  assert.ok(Math.abs(scale.x-scale.y)<.01,"WGC_GEOMETRY_MISMATCH");
  const marker={center:{x:config.to.x*scale.x,y:config.to.y*scale.y},radius:config.radius*scale.x,color:config.color};
  // The exact owned layered overlay is premultiplied even when WGC labels its copy straight.
  // Calibration preserves that API label; the converter rejects channels exceeding alpha.
  const rgb=whiteBackedRGB(bgra,meta.width,meta.height,"premultiplied");
  const sample={timeMs:(meta.tick100ns-origin)/10000,reportedAlphaMode:meta.alphaMode,analysisAlphaMode:"premultiplied",analysisBgraSha256:createHash("sha256").update(bgra).digest("hex"),...measureG08Frame(rgb,meta.width,meta.height,marker)};
  retention.push(sample);if(onProgress)onProgress({samples,frameCount:samples.length,shape});
 });
 assert.equal(count,samples.length);
 if(count===0)return {samples,analysis:null,oracleError:"INSUFFICIENT_EVIDENCE no frames",frameCount:0};
 if(config.pointerMs<1000)return {samples,analysis:null,oracleError:"FAST_PROFILE_NOT_DENSE",frameCount:count};
 try{
  const analysis=evaluateG08(samples,{...config,warmupCalibration:true,scale:{x:Number(shape.split(":")[0])/config.viewport.width,y:Number(shape.split(":")[1])/config.viewport.height}});
  return {samples,analysis,oracleError:null,frameCount:count};
 }catch(error){
  const message=String(error.message??"");
  const safe=/^(INSUFFICIENT_EVIDENCE|G08_)[A-Za-z0-9_ .:-]{0,120}$/.test(message)?message:"ORACLE_ERROR";
  return {samples,analysis:null,oracleError:safe,frameCount:count};
 }
}
