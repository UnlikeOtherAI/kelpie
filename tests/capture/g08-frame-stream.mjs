import assert from "node:assert/strict";
// One pending frame plus one bounded pipe chunk; no movie-sized raw buffer.
export async function consumeG08Frames(stream,width,height,onFrame){
  assert.ok(Number.isInteger(width)&&width>0&&width<=640);
  assert.ok(Number.isInteger(height)&&height>0&&height<=1600);
  const size=width*height*3;let frame=Buffer.allocUnsafe(size),used=0,count=0;
  for await(const chunk of stream){
    assert.ok(chunk.length<=1048576,"Decoded pipe chunk exceeds bound");
    let offset=0;
    while(offset<chunk.length){
      const length=Math.min(size-used,chunk.length-offset);
      chunk.copy(frame,used,offset,offset+length);used+=length;offset+=length;
      if(used===size){
        assert.ok(count<800,"Decoded frame limit exceeded");
        onFrame(frame,count++);frame=Buffer.allocUnsafe(size);used=0;
      }
    }
  }
  assert.equal(used,0,"Incomplete decoded RGB frame");
  return count;
}
