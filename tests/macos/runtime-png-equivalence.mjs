import {createHash} from "node:crypto";
import {execFileSync} from "node:child_process";
import {unlink} from "node:fs/promises";
function requireTrue(value,code){if(!value){const error=new Error(code);error.code=code;throw error;}}

// Only the owned fixture's exported PNG is decoded; no page content enters the receipt.
export function rgbaFacts(bytes,width,height){
 requireTrue(Number.isInteger(width)&&Number.isInteger(height)&&width>0&&height>0&&width*height<=1920*1920,"PIXEL_SIZE");
 requireTrue(bytes.length===width*height*4,"PIXEL_LENGTH");
 let min=255,max=0,nonopaque=0,blue=0,red=0;const colors=new Set();
 for(let i=0;i<bytes.length;i+=4){const r=bytes[i],g=bytes[i+1],b=bytes[i+2],a=bytes[i+3];
  min=Math.min(min,a);max=Math.max(max,a);if(a!==255)nonopaque++;
  if(b>r+30&&b>g+20)blue++;if(r>g+25&&r>b+25)red++;
  if(i%256===0&&colors.size<4096)colors.add((r<<16)|(g<<8)|b);
 }
 return {width,height,rgbaSHA256:createHash("sha256").update(bytes).digest("hex"),alpha:{min,max,nonopaque},pattern:{blue,red,sampledColors:colors.size}};
}
export function requireFixture(name,facts){
 const {blue,red,sampledColors}=facts.pattern;
 requireTrue(name==="static"?blue>500:name==="noisy"?sampledColors>500:name==="layered"?blue>500&&red>500:false,"PIXEL_FIXTURE_MISSING");
}
async function rendererViewport(client,tabId){
 const renderer=await client.api("get-renderer");
 const status=await client.api("browser-control",{version:1,method:"tab.status",tabId,params:{}});
 const v=status?.value?.viewport;
 requireTrue(renderer?.engine==="chromium"&&status?.ok===true&&Number.isInteger(v?.width)&&Number.isInteger(v?.height)&&v.width>0&&v.height>0,"PIXEL_RENDERER_VIEWPORT");
 return {engine:"chromium",width:v.width,height:v.height};
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
  const before=await rendererViewport(client,base.tabId);
  const start=process.hrtime.bigint();
  const result=await client.api("play-script",{...base,capture:{...capture,formats:["screenshots"],maxWidth:1280,fps:30},actions:[{action:"screenshot"}]});
  const elapsedMs=Number(process.hrtime.bigint()-start)/1e6;
  requireTrue(result.success,"PIXEL_WORKFLOW");
  const after=await rendererViewport(client,base.tabId);
  requireTrue(JSON.stringify(before)===JSON.stringify(after),"PIXEL_RENDERER_VIEWPORT_CHANGED");
  client.verifyOwnedReveal();client.pin(28420);
  requireTrue((await client.windows()).some(item=>item.id===window.id&&item.isKey),"PIXEL_WINDOW_CHANGED");
  const images=await client.download(result,"pixel-"+name,privateDir);
  requireTrue(images.length===1&&images[0].mimeType==="image/png","PIXEL_ARTIFACT");
  const item=images[0];
  try{
   const rgba=execFileSync("ffmpeg",["-v","error","-threads","1","-i",item.file,"-frames:v","1","-f","rawvideo","-pix_fmt","rgba","-"],{maxBuffer:16*1024*1024});
   const facts=rgbaFacts(rgba,item.width,item.height);requireFixture(name,facts);
   return {name,elapsedMs,encodedBytes:item.byteLength,viewport:before,...facts,alphaScope:"composited-export"};
  }finally{await unlink(item.file);}
 },{continueOnFailure:true});
}
