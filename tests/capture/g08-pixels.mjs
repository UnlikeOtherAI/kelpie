import assert from "node:assert/strict";
export const median = values => [...values].sort((a,b)=>a-b)[Math.floor(values.length/2)];
export function measureG08Frame(rgb, width, height, { center, radius, color }) {
  assert.ok(Number.isInteger(width)&&width>0&&width<=640);
  assert.ok(Number.isInteger(height)&&height>0&&height<=1600);
  assert.equal(rgb.length,width*height*3);
  const expected=color.match(/[a-f0-9]{2}/gi)?.map(value=>parseInt(value,16));
  assert.equal(expected?.length,3);
  const high=expected.indexOf(Math.max(...expected)), low=expected.indexOf(Math.min(...expected));
  const contrast=expected[high]-expected[low];
  assert.ok(contrast>=160,"Use a contrasting chromatic marker");
  let x0=width,y0=height,x1=-1,y1=-1,dark=0;
  for(let y=2;y<height-2;y++)for(let x=2;x<width-2;x++){
    const i=(y*width+x)*3;
    if(Math.max(rgb[i],rgb[i+1],rgb[i+2])<100){
      dark++;x0=Math.min(x0,x);x1=Math.max(x1,x);y0=Math.min(y0,y);y1=Math.max(y1,y);
    }
  }
  const pointer=dark>=5&&dark<=1800&&x1-x0<=64&&y1-y0<=64?{x:x0,y:y0,dark}:null;
  const sample=[];
  const sx=Math.round(center.x-radius*.45),sy=Math.round(center.y);
  for(let y=sy-1;y<=sy+1;y++)for(let x=sx-1;x<=sx+1;x++){
    assert.ok(x>=0&&x<width&&y>=0&&y<height,"Marker sample outside frame");
    const i=(y*width+x)*3;sample.push([rgb[i],rgb[i+1],rgb[i+2]]);
  }
  const channels=[0,1,2].map(c=>median(sample.map(pixel=>pixel[c])));
  const alpha=Math.max(0,Math.min(1,(channels[high]-channels[low])/contrast));
  const threshold=Math.max(12,(channels[high]-channels[low])*.4);
  let minX=width,minY=height,maxX=-1,maxY=-1,count=0,chromaticCount=0;
  const span=Math.ceil(radius*1.3+3);
  for(let y=Math.max(0,Math.floor(center.y-span));y<=Math.min(height-1,Math.ceil(center.y+span));y++)
    for(let x=Math.max(0,Math.floor(center.x-span));x<=Math.min(width-1,Math.ceil(center.x+span));x++){
      const i=(y*width+x)*3;
      if(Math.max(rgb[i],rgb[i+1],rgb[i+2])-Math.min(rgb[i],rgb[i+1],rgb[i+2])>=16)chromaticCount++;
      if(rgb[i+high]-rgb[i+low]>=threshold){
        count++;minX=Math.min(minX,x);maxX=Math.max(maxX,x);minY=Math.min(minY,y);maxY=Math.max(maxY,y);
      }
    }
  return {pointer,marker:{alpha,channels,count,chromaticCount,
    radius:count?((maxX-minX+1)+(maxY-minY+1))/4:null,
    center:count?{x:(minX+maxX)/2,y:(minY+maxY)/2}:null}};
}
