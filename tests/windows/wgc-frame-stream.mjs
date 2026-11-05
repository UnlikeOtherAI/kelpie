import assert from "node:assert/strict";
const MAX_HEADER=4096,MAX_PIXELS=640*1600,MAX_PAYLOAD=MAX_PIXELS*4,MAX_FRAMES=520;
export function expectedAnalysisSize(sourceWidth,sourceHeight){
 assert.ok(Number.isInteger(sourceWidth)&&sourceWidth>0&&Number.isInteger(sourceHeight)&&sourceHeight>0,"WGC_ANALYSIS_SIZE");
 const scale=Math.min(1,640/sourceWidth,1920/sourceHeight);
 assert.ok(sourceWidth*scale>=2&&sourceHeight*scale>=2,"WGC_ANALYSIS_SIZE");
 const width=Math.max(2,Math.floor(sourceWidth*scale/2)*2),height=Math.max(2,Math.floor(sourceHeight*scale/2)*2);
 assert.ok(width<=640&&height<=1600,"WGC_ANALYSIS_SIZE");return {width,height};
}
// The async consumer imposes backpressure; no frame backlog is accumulated.
export async function consumeWgcFrames(stream,onFrame){
 let parts=[],held=0,need=8,state="prefix",headerLength=0,payloadLength=0,metadata,count=0,lastTick=-1,firstTick=-1,lastReceipt=-1,shape;
 async function take(bytes){
  while(bytes.length){
   const n=Math.min(need-held,bytes.length);parts.push(bytes.subarray(0,n));held+=n;bytes=bytes.subarray(n);
   if(held!==need)continue;
   const value=Buffer.concat(parts,need);parts=[];held=0;
   if(state==="prefix"){
    headerLength=value.readUInt32LE(0);payloadLength=value.readUInt32LE(4);
    assert.ok(headerLength>0&&headerLength<=MAX_HEADER&&payloadLength>0&&payloadLength<=MAX_PAYLOAD,"WGC_RECORD_BOUND");
    need=headerLength;state="header";
   }else if(state==="header"){
    metadata=JSON.parse(value.toString("utf8"));
    assert.ok(Number.isSafeInteger(metadata.sequence)&&metadata.sequence===count,"WGC_SEQUENCE");
    assert.ok(Number.isSafeInteger(metadata.tick100ns)&&metadata.tick100ns>lastTick,"WGC_CLOCK");
    if(firstTick<0)firstTick=metadata.tick100ns;
    assert.ok(metadata.tick100ns-firstTick<=260000000,"WGC_DURATION_BOUND");
    assert.ok(Number.isSafeInteger(metadata.receiptMs)&&metadata.receiptMs>=lastReceipt,"WGC_RECEIPT_CLOCK");
    assert.ok(Number.isInteger(metadata.sourceWidth)&&metadata.sourceWidth>0&&metadata.sourceWidth<=4096);
    assert.ok(Number.isInteger(metadata.sourceHeight)&&metadata.sourceHeight>0&&metadata.sourceHeight<=4096&&metadata.sourceWidth*metadata.sourceHeight<=2097152);
    assert.equal(metadata.sourceStride,metadata.sourceWidth*4,"WGC_SOURCE_STRIDE");
    assert.ok(Number.isInteger(metadata.width)&&metadata.width>0&&metadata.width<=640);
    assert.ok(Number.isInteger(metadata.height)&&metadata.height>0&&metadata.height<=1600);
    const expected=expectedAnalysisSize(metadata.sourceWidth,metadata.sourceHeight);
    assert.equal(metadata.width,expected.width,"WGC_ANALYSIS_WIDTH");
    assert.equal(metadata.height,expected.height,"WGC_ANALYSIS_HEIGHT");
    assert.equal(payloadLength,metadata.width*metadata.height*4,"WGC_PAYLOAD_SIZE");
    assert.ok(["straight","premultiplied"].includes(metadata.alphaMode),"WGC_ALPHA_MODE");
    const current=[metadata.width,metadata.height,metadata.sourceWidth,metadata.sourceHeight,metadata.alphaMode].join(":");
    if(shape)assert.equal(current,shape,"WGC_SIZE_CHANGED");else shape=current;
    need=payloadLength;state="payload";
   }else{
    assert.ok(count<MAX_FRAMES,"WGC_FRAME_LIMIT");lastTick=metadata.tick100ns;lastReceipt=metadata.receiptMs;
    await onFrame(value,metadata);count++;need=8;state="prefix";
   }
  }
 }
 for await(const chunk of stream){assert.ok(Buffer.isBuffer(chunk)&&chunk.length<=MAX_PAYLOAD+MAX_HEADER+8,"WGC_CHUNK_BOUND");await take(chunk);}
 assert.equal(state,"prefix","WGC_TRUNCATED");assert.equal(held,0,"WGC_TRUNCATED");return count;
}
