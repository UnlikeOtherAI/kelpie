import assert from "node:assert/strict";
import {execFile} from "node:child_process";
import {createServer} from "node:http";
import {readFile,writeFile,mkdir} from "node:fs/promises";
import {isAbsolute,resolve} from "node:path";
import {promisify} from "node:util";
import {downloadArtifacts} from "./capture-artifact-download.mjs";

const [readinessPath,outputPath]=process.argv.slice(2);
assert.ok(readinessPath&&outputPath);
const readiness=JSON.parse(await readFile(readinessPath,"utf8"));
assert.equal(readiness.controlMode,"loopback");
const expected=process.env.KELPIE_CAPTURE_RECEIPT_FIXTURE_URL;
assert.match(expected??"",/^http:\/\/127\.0\.0\.1:[0-9]{1,5}$/);
const port=Number(new URL(expected).port);
assert.ok(Number.isInteger(port)&&port>0&&port<=65535);
assert.ok(isAbsolute(process.env.FFMPEG??""));
const output=resolve(outputPath);await mkdir(output,{recursive:false});
const sockets=new Set();
const server=createServer((request,response)=>{
 const colors={"/":"#ff0000","/next":"#0000ff"};
 const color=colors[request.url];
 if(request.method!=="GET"||!color){response.writeHead(404);response.end();return;}
 const body='<!doctype html><meta charset="utf-8"><style>html,body{margin:0;width:100%;height:100%;background:'+color+'}</style>';
 response.writeHead(200,{"content-type":"text/html; charset=utf-8","cache-control":"no-store",
  "content-length":Buffer.byteLength(body)});response.end(body);
});
server.on("connection",socket=>{sockets.add(socket);socket.once("close",()=>sockets.delete(socket));});
await new Promise((resolve,reject)=>{server.once("error",reject);server.listen(port,"127.0.0.1",resolve);});
const checks=[],artifacts=[];
const api=async(method,body={})=>{
 const response=await fetch("http://127.0.0.1:"+readiness.port+"/v1/"+method,{
  method:"POST",headers:{authorization:"Bearer "+readiness.token,"content-type":"application/json"},
  body:JSON.stringify(body),signal:AbortSignal.timeout(60000)});
 return response.json();
};
const exec=promisify(execFile);
async function roi(path){
 const {stdout}=await exec(process.env.FFMPEG,["-v","error","-i",path,"-vf","crop=2:2:20:20,format=rgb24",
  "-frames:v","1","-f","rawvideo","pipe:1"],{encoding:"buffer",windowsHide:true,timeout:30000,maxBuffer:1024});
 assert.equal(stdout.length,12);return [...stdout];
}
function matches(pixels,channel){
 for(let i=0;i<pixels.length;i+=3) for(let c=0;c<3;c++)
  assert.ok(c===channel ? pixels[i+c]>=240 : pixels[i+c]<=15,"FIXTURE_ROI_MISMATCH");
}
try{
 const tabs=await api("get-tabs"),tabId=(tabs.tabs??[]).find(tab=>tab.active)?.id;assert.ok(tabId);
 assert.equal((await api("navigate",{tabId,url:expected})).success,true);
 assert.equal((await api("play-script",{version:1,tabId,actions:[{action:"wait-ready",state:"complete"}]})).success,true);
 const old=await api("screenshot",{tabId,format:"png"});
 assert.equal(old.success,true);assert.equal(old.format,"png");
 const oldBytes=Buffer.from(old.image,"base64");assert.ok(oldBytes.length>0&&oldBytes.length<=8388608);
 const oldPath=resolve(output,"old-control.png");await writeFile(oldPath,oldBytes,{flag:"wx"});
 const oldPixels=await roi(oldPath);matches(oldPixels,0);
 const result=await api("play-script",{version:1,tabId,actions:[{action:"wait",ms:300},{action:"screenshot",name:"after"}],
  pointer:{enabled:false},capture:{formats:["screenshots"],fps:5,maxWidth:640,maxBytes:8388608,maxDurationMs:20000}});
 assert.equal(result.success,true);assert.equal(result.actionsExecuted,2);
 const png=result.artifacts.find(item=>item.mimeType==="image/png"&&item.actionIndex===1&&item.documentId);
 assert.ok(png);assert.equal((await api("get-current-url",{tabId})).url,expected+"/next");
 await downloadArtifacts(result,{api,output,artifacts});
 const newPixels=await roi(resolve(output,png.id+".png"));matches(newPixels,2);
 assert.equal((await api("navigate",{tabId,url:expected})).success,true);
 assert.equal((await api("play-script",{version:1,tabId,actions:[{action:"wait-ready",state:"complete"}]})).success,true);
 assert.equal((await api("play-script",{version:1,tabId,actions:[{action:"wait",ms:0}]})).success,true);
 checks.push({name:"receipt checkpoint navigation drops old frame and recovers",passed:true,oldPixels,newPixels});
}catch(error){
 const code=typeof error?.code==="string"&&/^[A-Z][A-Z0-9_]{0,79}$/.test(error.code)?error.code:null;
 checks.push({name:"receipt checkpoint navigation drops old frame and recovers",passed:false,code});
 process.exitCode=1;
}finally{
 let cleanup="closed";
 try{await new Promise((resolve,reject)=>{server.close(error=>error?reject(error):resolve());for(const socket of sockets)socket.destroy();});}
 catch{cleanup="failed";process.exitCode=1;}
 await writeFile(resolve(output,"report.json"),JSON.stringify({checks,artifacts,cleanup},null,2),{flag:"wx"});
}
