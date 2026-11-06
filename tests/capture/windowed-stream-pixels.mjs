import assert from "node:assert/strict";

// Only use on decoded, finally sealed frames from the synthetic owned fixture.
export function measureWindowedStreamFrame(rgb,width,height,viewport,visualNonce){
 assert.ok(Number.isInteger(width)&&Number.isInteger(height)&&width>0&&height>0&&width*height<=2073600);
 assert.ok(rgb instanceof Uint8Array&&rgb.length===width*height*3);
 assert.ok(Number.isInteger(visualNonce)&&visualNonce>=0&&visualNonce<=65535);
 const sx=width/viewport.width,sy=height/viewport.height;
 assert.ok(Number.isFinite(sx)&&Number.isFinite(sy)&&sx>0&&sy>0);
 function cell(x){
  const px=Math.floor(x*sx),py=Math.floor(14*sy);assert.ok(px>=0&&px<width&&py>=0&&py<height);
  const offset=(py*width+px)*3,channels=[rgb[offset],rgb[offset+1],rgb[offset+2]];
  if(channels.every(value=>value<32))return 1;
  if(channels.every(value=>value>223))return 0;
  throw Error("STREAM_NONCE_PIXEL_INVALID");
 }
 assert.equal(cell(142),1,"STREAM_NONCE_REFERENCE");assert.equal(cell(150),0,"STREAM_NONCE_REFERENCE");
 let observed=0;for(let index=0;index<16;index++)observed|=cell(14+8*index)<<index;
 assert.equal(observed,visualNonce,"STREAM_NONCE_MISMATCH");
 let minX=width,minY=height,maxX=-1,maxY=-1,count=0;
 for(let y=0;y<height;y++)for(let x=0;x<width;x++){
  const offset=(y*width+x)*3;
  if(rgb[offset]>=225&&rgb[offset+1]<70&&rgb[offset+2]<90){
   minX=Math.min(minX,x);maxX=Math.max(maxX,x);minY=Math.min(minY,y);maxY=Math.max(maxY,y);count++;
  }
 }
 assert.ok(count>=16,"STREAM_SYNTHETIC_DOT_MISSING");
 return {x:(minX+maxX+1)/(2*sx),y:(minY+maxY+1)/(2*sy),pixelCount:count};
}
