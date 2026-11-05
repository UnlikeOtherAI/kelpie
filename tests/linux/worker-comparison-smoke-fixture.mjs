import assert from "node:assert/strict";
import {createServer} from "node:http";
export async function startSmokeFixture(nonce){
 assert.match(nonce,/^[a-f0-9]{64}$/);
 let resolveCanary;
 const canary=new Promise(ok=>{resolveCanary=ok;});
 const server=createServer((req,res)=>{
  res.setHeader("cache-control","no-store");
  if(req.method!=="GET"){res.writeHead(405);res.end();return;}
  if(req.url==="/"){
   res.setHeader("content-type","text/html; charset=utf-8");
   res.end('<!doctype html><title>Sandbox smoke</title><script>fetch("/canary/'+nonce+'",{cache:"no-store"});</script>');
  }else if(req.url==="/canary/"+nonce){res.writeHead(204);res.end();resolveCanary(true);}
  else {res.writeHead(404);res.end();}
 });
 await new Promise((ok,bad)=>{server.once("error",bad);server.listen(0,"127.0.0.1",ok);});
 const origin="http://127.0.0.1:"+server.address().port;
 return {origin,async waitForCanary(ms){
  let timer;try{return await Promise.race([canary,new Promise(ok=>{timer=setTimeout(()=>ok(false),ms);})]);}
  finally{clearTimeout(timer);}
 },async close(){server.closeAllConnections?.();await new Promise(ok=>server.close(ok));}};
}
