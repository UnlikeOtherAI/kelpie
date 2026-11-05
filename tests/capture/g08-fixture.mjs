import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";
export async function startG08Fixture({host="127.0.0.1",port=0}={}){
  assert.ok(Number.isInteger(port)&&port>=0&&port<=65535);
  const html=await readFile(new URL("./g08-fixture.html",import.meta.url));
  const events=[],sockets=new Set();let dropped=0,pageRequests=0;
  const send=(response,status,body,type="application/json")=>{
    response.writeHead(status,{"content-type":type,"cache-control":"no-store","content-length":Buffer.byteLength(body)});
    response.end(body);
  };
  const server=createServer((request,response)=>{void(async()=>{
    const path=new URL(request.url??"/","http://fixture.invalid").pathname;
    if(request.method==="GET"&&(path==="/"||path==="/g08")){pageRequests++;return send(response,200,html,"text/html; charset=utf-8");}
    if(request.method==="POST"&&path==="/events"){
      const chunks=[];let bytes=0;
      for await(const chunk of request){bytes+=chunk.length;if(bytes>8192)return send(response,413,"{}");chunks.push(chunk);}
      try{
        const fact=JSON.parse(Buffer.concat(chunks).toString("utf8"));
        assert.ok(fact&&["start","finish"].includes(fact.target)&&typeof fact.documentId==="string"&&fact.documentId.length<=128);
        assert.ok([fact.timeMs,fact.center?.x,fact.center?.y,fact.viewport?.width,fact.viewport?.height].every(Number.isFinite));
        assert.equal(typeof fact.trusted,"boolean");
        if(events.length<20)events.push(fact);else dropped++;
        return send(response,202,"{}");
      }catch{return send(response,400,"{}");}
    }
    if(request.method==="GET"&&path==="/events")return send(response,200,JSON.stringify({events,dropped}));
    send(response,404,"{}");
  })().catch(()=>{if(!response.headersSent)send(response,500,"{}");else response.destroy();});});
  server.requestTimeout=5000;server.headersTimeout=5000;
  server.on("connection",socket=>{sockets.add(socket);socket.once("close",()=>sockets.delete(socket));});
  await new Promise((resolve,reject)=>{server.once("error",reject);server.listen(port,host,resolve);});
  const address=server.address();
  return {url:"http://"+host+":"+address.port+"/g08",events,get pageRequests(){return pageRequests;},
    close:()=>new Promise(resolve=>{server.close(resolve);for(const socket of sockets)socket.destroy();})};
}
export function g08Workflow(tabId,curve="c"){
  assert.ok(typeof tabId==="string"&&tabId.length>0&&tabId.length<=256);
  assert.ok(["c","s"].includes(curve));
  return {version:1,tabId,pointer:{enabled:true,curve,durationMs:2400,easing:"ease-in-out"},
    tapIndicator:{color:curve==="c"?"#ff0000":"#0000ff",radius:48,durationMs:3000,wobble:true,fade:true},
    capture:{formats:["gif","video"],fps:20,maxWidth:640,maxDurationMs:33000,maxBytes:33554432},
    actions:[{action:"click",target:{role:"button",name:"G08 Finish",exact:true}},
      {action:"wait",ms:3500},{action:"click",target:{role:"button",name:"G08 Finish",exact:true}},
      {action:"wait",ms:3500},{action:"click",target:{role:"button",name:"G08 Start",exact:true}},
      {action:"wait",ms:3500},{action:"click",target:{role:"button",name:"G08 Finish",exact:true}},
      {action:"wait",ms:3500}]};
}

/** Bind four independently observed, ordered clicks to the same fixture scene. */
export function mapG08Scene(events){
  assert.ok(Array.isArray(events)&&events.length===4);
  assert.deepEqual(events.map(event=>event.target),["finish","finish","start","finish"]);
  const [warmup,calibration,start,finish]=events;
  assert.ok(typeof warmup.documentId==="string"&&warmup.documentId.length>0&&warmup.documentId.length<=128);
  for(const [index,event] of events.entries()){
    assert.equal(event.documentId,warmup.documentId);
    assert.ok([event.center?.x,event.center?.y,event.viewport?.width,event.viewport?.height].every(Number.isFinite));
    assert.ok(event.viewport.width>0&&event.viewport.height>0);
    assert.deepEqual(event.viewport,warmup.viewport);
    assert.deepEqual(event.visualViewport,warmup.visualViewport);
    assert.equal(typeof event.trusted,"boolean");
    assert.ok(Number.isFinite(event.timeMs)&&(index===0||event.timeMs>events[index-1].timeMs));
  }
  assert.ok(calibration.timeMs-warmup.timeMs>=3500,"Warmup did not clear before calibration");
  assert.deepEqual(warmup.center,calibration.center);
  assert.deepEqual(calibration.center,finish.center);
  return {warmup,calibration,start,finish};
}