import {createHash} from "node:crypto";
import {execFileSync} from "node:child_process";
import {unlink} from "node:fs/promises";
function requireTrue(value,code){if(!value){const error=new Error(code);error.code=code;throw error;}}

// Only the owned fixture's exported PNG is decoded; no page content enters the receipt.
export function rgbaFacts(bytes,width,height){
 requireTrue(Number.isInteger(width)&&Number.isInteger(height)&&width>0&&height>0&&width*height<=1920*1920,"PIXEL_SIZE");
 requireTrue(bytes.length===width*height*4,"PIXEL_LENGTH");
 let min=255,max=0,nonopaque=0;
 for(let i=3;i<bytes.length;i+=4){min=Math.min(min,bytes[i]);max=Math.max(max,bytes[i]);if(bytes[i]!==255)nonopaque++;}
 return {width,height,rgbaSHA256:createHash("sha256").update(bytes).digest("hex"),alpha:{min,max,nonopaque}};
}
export async function runPngEquivalence({client,engine,base,capture,check,load,privateDir}){
 requireTrue(engine==="chromium","FOCUSED_RENDERER");
 client.verifyOwnedReveal();client.pin(28420);
 const window=(await client.windows()).find(item=>item.isKey);
 requireTrue(window?.id,"PIXEL_WINDOW");
 for(const name of ["static","noisy","layered"])await check("png-equivalence-"+name,async()=>{
  await load("/pixels-"+name);
  client.verifyOwnedReveal();client.pin(28420);
  requireTrue((await client.windows()).some(item=>item.id===window.id&&item.isKey),"PIXEL_WINDOW_CHANGED");
  const start=process.hrtime.bigint();
  const result=await client.api("play-script",{...base,capture:{...capture,formats:["screenshots"],maxWidth:1280},actions:[{action:"screenshot"}]});
  const elapsedMs=Number(process.hrtime.bigint()-start)/1e6;
  requireTrue(result.success,"PIXEL_WORKFLOW");
  client.verifyOwnedReveal();client.pin(28420);
  requireTrue((await client.windows()).some(item=>item.id===window.id&&item.isKey),"PIXEL_WINDOW_CHANGED");
  const images=await client.download(result,"pixel-"+name,privateDir);
  requireTrue(images.length===1&&images[0].mimeType==="image/png","PIXEL_ARTIFACT");
  const item=images[0];
  try{
   const rgba=execFileSync("ffmpeg",["-v","error","-threads","1","-i",item.file,"-frames:v","1","-f","rawvideo","-pix_fmt","rgba","-"],{maxBuffer:16*1024*1024});
   return {name,elapsedMs,encodedBytes:item.byteLength,...rgbaFacts(rgba,item.width,item.height),alphaScope:"composited-export"};
  }finally{await unlink(item.file);}
 },{continueOnFailure:true});
}
