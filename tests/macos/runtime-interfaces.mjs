import {writeFile,mkdir,readFile} from "node:fs/promises";
import path from "node:path";
import {createHash} from "node:crypto";
import {inspectMedia} from "./runtime-media.mjs";
import {cli,cliMCP,requireTrue,waitFor} from "./runtime-client.mjs";
export async function publicCLI(client,fixture,privateDir,engine="webkit"){
 if(engine==="webkit"){
  client.cliStage="pair";
  const pairing=cli(["pair","--client-name","Hosted public CLI","--timeout-ms","35000"]);
  void pairing.result.catch(()=>{});
  const window=await waitFor(()=>client.find("pair.dialog.always"));
  await client.tap("pair.dialog.always",window);await pairing.result;
 }
 client.cliStage="get-tabs";
 const tabs=await client.api("get-tabs");const tabId=engine==="chromium"?"chromium":tabs.activeTab;
 requireTrue(tabId,engine==="chromium"?"CLI_CEF_TAB":"CLI_WEBKIT_TAB");
 const file=path.join(privateDir,"recipe-"+engine+".json"),inputs=path.join(privateDir,"inputs-"+engine+".json"),out=path.join(client.out,"cli-"+engine);
 await mkdir(out,{recursive:true});
 await writeFile(file,JSON.stringify({version:1,tabId,inputs:{draft:{type:"string"}},capture:{formats:["gif","video","screenshots"],fps:5,maxWidth:640,maxDurationMs:15000,maxBytes:33554432},
 actions:[{action:"navigate",url:fixture.url},{action:"wait-ready",state:"complete"},
 {action:"fill",target:{label:"Draft message"},text:{input:"draft"}},{action:"click",target:{role:"button",name:"Submit"}}]}),{flag:"wx"});
 await writeFile(inputs,JSON.stringify({draft:"Public CLI typed input"}),{flag:"wx"});
 client.pin(28420);
 client.cliStage="run";
 const response=await cli(["script","run",file,"--inputs",inputs,"--output",out],90000).result;
 client.pin(28420);const value=response.result??response;
 requireTrue(response.downloaded?.length>0,"PUBLIC_CLI_DOWNLOADS");
 requireTrue(value.success,"PUBLIC_CLI_WORKFLOW");
 client.cliStage="status";
 const status=await cli(["script","status","--run-id",value.runId,"--pinned"]).result;
 requireTrue(status.supportedVersions?.includes(1)&&status.runSuccess,"PUBLIC_CLI_PINNED_STATUS");
 client.cliStage="downloads";
 const decoded=[];let total=0;
 for(const saved of response.downloaded){
  const artifact=value.artifacts.find(item=>item.id===saved.id);requireTrue(artifact,"PUBLIC_CLI_ARTIFACT_ID");
  total+=artifact.byteLength;requireTrue(total<=33554432,"PUBLIC_CLI_AGGREGATE_BYTES");
  const bytes=await readFile(saved.file);requireTrue(bytes.length===artifact.byteLength&&createHash("sha256").update(bytes).digest("hex")===artifact.sha256,"PUBLIC_CLI_DISK_HASH");
  decoded.push(inspectMedia({...artifact,file:saved.file}));
 }
 requireTrue(new Set(decoded.map(item=>item.mimeType)).size===3,"PUBLIC_CLI_ALL_FORMATS");
 client.cliStage="mcp";
 const mcp=await cliMCP();
 return {engine,runId:value.runId,status:status.state,downloaded:true,decoded,mcp};
}
export async function inference(client,privateDir){
 const revision="499bc8821c6b12b4e53c5bffcb21ec206f212d81";
 const response=await fetch("https://huggingface.co/ggml-org/models-moved/resolve/"+revision+"/tinyllamas/stories15M-q4_0.gguf",{signal:AbortSignal.timeout(60000)});
 requireTrue(response.ok,"MODEL_DOWNLOAD");
 const chunks=[];let length=0;for await(const bytes of response.body){length+=bytes.length;requireTrue(length<=20000000,"MODEL_BYTE_LIMIT");chunks.push(Buffer.from(bytes));}
 const model=Buffer.concat(chunks),sha256=createHash("sha256").update(model).digest("hex");
 requireTrue(length===19077344&&sha256==="66967fbece6dbe97886593fdbb73589584927e29119ec31f08090732d1861739","MODEL_HASH");
 const file=path.join(privateDir,"stories15M-q4_0.gguf");await writeFile(file,model,{flag:"wx"});
 const loaded=await client.api("ai-load",{path:file});requireTrue(loaded.success,"MODEL_LOAD");
 let failed=false;
 try{
  const status=await waitFor(async()=>{const value=await client.api("ai-status");return value.loaded&&value.backend==="native"?value:null;});
  const value=await client.api("ai-infer",{messages:[{role:"user",content:"Once upon a time"}],text:"Synthetic fixture.",prompt:"Continue briefly.",maxTokens:8,temperature:0});
  requireTrue(value.success&&typeof value.response==="string"&&value.tokensUsed>0,"NATIVE_INFERENCE");
  return {revision,sha256,bytes:length,backend:status.backend,tokensUsed:value.tokensUsed,inferenceTimeMs:value.inferenceTimeMs,gpuExecution:"not exposed"};
 }catch(error){failed=true;throw error;}finally{
  try{const unloaded=await client.api("ai-unload");requireTrue(unloaded.success,"MODEL_UNLOAD");
   await waitFor(async()=>{const value=await client.api("ai-status");return value.loaded===false;});
  }catch(error){if(!failed)throw error;}
 }
}
