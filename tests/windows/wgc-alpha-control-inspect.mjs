import assert from "node:assert/strict";
import {whiteBackedRGB} from "./wgc-g08-rgb.mjs";

// Coordinates alone are mapped from the control's 320x160 logical surface.
export function inspectAlphaControl(raw,decoded,width,height){
 assert.ok(Number.isInteger(width)&&Number.isInteger(height)&&width>=320&&height>=160&&width<=1280&&height<=640);
 assert.equal(width*160,height*320,"CONTROL_ASPECT_CHANGED");
 assert.equal(raw.length,width*height*4);assert.equal(decoded.length,raw.length);
 const sx=width/320,sy=height/160;
 return [["red",50,[0,0,178,178]],["green",150,[0,89,0,89]],["blue",250,[255,0,0,255]],["clear",310,[0,0,0,0]]].map(([name,logicalX,inputBgra])=>{
  const x=Math.floor(logicalX*sx),y=Math.floor(80*sy),samples=[];
  for(let yy=y-1;yy<=y+1;yy++)for(let xx=x-1;xx<=x+1;xx++){
   const at=(yy*width+xx)*4,pixel=raw.subarray(at,at+4);let premultiplied=null;
   try{premultiplied=[...whiteBackedRGB(pixel,1,1,"premultiplied")];}catch{}
   samples.push({rawBgra:[...pixel],pngRgba:[...decoded.subarray(at,at+4)],
    whiteStraight:[...whiteBackedRGB(pixel,1,1,"straight")],whitePremultiplied:premultiplied});
  }
  return {name,x,y,inputBgra,samples};
 });
}
