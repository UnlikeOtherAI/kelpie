import assert from "node:assert/strict";
// Numeric analysis only: native pixels remain untouched in the evidence files.
export function whiteBackedRGB(bgra,width,height,alphaMode){
 assert.ok(Number.isInteger(width)&&width>0&&width<=640);
 assert.ok(Number.isInteger(height)&&height>0&&height<=1600);
 assert.ok(Buffer.isBuffer(bgra)&&bgra.length===width*height*4);
 assert.ok(["straight","premultiplied"].includes(alphaMode));
 const rgb=Buffer.allocUnsafe(width*height*3);
 for(let src=0,dst=0;src<bgra.length;src+=4,dst+=3){
  const alpha=bgra[src+3];
  for(let channel=0;channel<3;channel++){
   const value=bgra[src+2-channel];
   if(alphaMode==="premultiplied")assert.ok(value<=alpha+1,"INVALID_PREMULTIPLIED_ALPHA");
   rgb[dst+channel]=alphaMode==="straight"
    ?Math.round((value*alpha+255*(255-alpha))/255)
    :Math.min(255,value+255-alpha);
  }
 }
 return rgb;
}
