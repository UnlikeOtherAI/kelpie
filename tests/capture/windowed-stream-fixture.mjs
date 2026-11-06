import assert from "node:assert/strict";
import {randomBytes} from "node:crypto";
import {createServer} from "node:http";

// Synthetic test fixture only: the nonce is a routing check, not authority.
export async function startWindowedStreamFixture(){
 const nonce=randomBytes(16).toString("hex"),sockets=new Set();let requests=0;
 const server=createServer((request,response)=>{
  if(request.method!=="GET"||++requests>16){response.writeHead(429).end();return;}
  const url=new URL(request.url,"http://fixture.invalid");
  const mode=url.pathname===`/${nonce}/animated`?"animated":url.pathname===`/${nonce}/static`?"static":null;
  if(!mode||url.search||url.hash){response.writeHead(404).end();return;}
  const animation=mode==="animated"?"animation:move 2s linear infinite alternate;":"";
  const visualNonce=Number.parseInt(nonce.slice(0,4),16);
  const cells=Array.from({length:16},(_,index)=>`<i style="left:${10+index*8}px;background:${visualNonce&(1<<index)?"#000":"#fff"}"></i>`).join("")+
   '<i style="left:138px;background:#000"></i><i style="left:146px;background:#fff"></i>';
  const html=`<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><style>
html,body{margin:0;background:white;overflow:hidden}#dot{position:absolute;left:30px;top:120px;width:30px;height:30px;background:#f52233;${animation}}
@keyframes move{to{transform:translateX(500px)}}i{position:absolute;top:10px;width:8px;height:8px}</style>${cells}<div id="dot"></div>`;
  response.writeHead(200,{"content-type":"text/html; charset=utf-8","cache-control":"no-store",
   "content-length":Buffer.byteLength(html)}).end(html);
 });
 server.on("connection",socket=>{sockets.add(socket);socket.once("close",()=>sockets.delete(socket));});
 await new Promise((resolve,reject)=>{server.once("error",reject);server.listen(0,"127.0.0.1",resolve);});
 const port=server.address().port;assert.ok(Number.isInteger(port));
 const origin=`http://127.0.0.1:${port}`;
 return {origin,nonce,visualNonce:Number.parseInt(nonce.slice(0,4),16),animated:`${origin}/${nonce}/animated`,static:`${origin}/${nonce}/static`,
  close:()=>new Promise(resolve=>{for(const socket of sockets)socket.destroy();server.close(resolve);})};
}
