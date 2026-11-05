import {writeFile,mkdir} from "node:fs/promises";
import path from "node:path";
import {createHash} from "node:crypto";
import {cli,cliMCP,requireTrue,waitFor} from "./runtime-client.mjs";
export async function publicCLI(client,fixture,privateDir){
 const pairing=cli(["pair","--client-name","Hosted public CLI","--timeout-ms","35000"]);
 const window=await waitFor(()=>client.find("pair.dialog.always"));
 await client.tap("pair.dialog.always",window);await pairing.result;
 const tabs=await client.api("get-tabs");const tabId=tabs.activeTab;
 requireTrue(tabId,"CLI_WEBKIT_TAB");
 const file=path.join(privateDir,"recipe.json"),inputs=path.join(privateDir,"inputs.json"),out=path.join(client.out,"cli");
 await mkdir(out,{recursive:true});
 await writeFile(file,JSON.stringify({version:1,tabId,inputs:{draft:{type:"string"}},capture:{formats:["gif","video","screenshots"],fps:5,maxWidth:640,maxDurationMs:15000,maxBytes:33554432},
 actions:[{action:"navigate",url:fixture.url},{action:"wait-ready",state:"complete"},
 {action:"fill",target:{label:"Draft message"},text:{input:"draft"}},{action:"click",target:{role:"button",name:"Submit"}}]}),{flag:"wx"});
 await writeFile(inputs,JSON.stringify({draft:"Public CLI typed input"}),{flag:"wx"});
 client.pin(28420);
 const response=await cli(["script","run",file,"--inputs",inputs,"--output",out],90000).result;
 client.pin(28420);const value=response.result??response;
 requireTrue(response.downloaded?.length>0,"PUBLIC_CLI_DOWNLOADS");
 requireTrue(value.success,"PUBLIC_CLI_WORKFLOW");
 const status=await cli(["script","status","--run-id",value.runId,"--pinned"]).result;
 requireTrue(status.supportedVersions?.includes(1)&&status.runSuccess,"PUBLIC_CLI_PINNED_STATUS");
 const mcp=await cliMCP();
 return {runId:value.runId,status:status.state,downloaded:true,mcp};
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
 try{
  const status=await client.api("ai-status");requireTrue(status.loaded&&status.backend==="native","NATIVE_AI_STATUS");
  const value=await client.api("ai-infer",{messages:[{role:"user",content:"Once upon a time"}],text:"Synthetic fixture.",prompt:"Continue briefly.",maxTokens:8,temperature:0});
  requireTrue(value.success&&typeof value.response==="string"&&value.tokensUsed>0,"NATIVE_INFERENCE");
  return {revision,sha256,bytes:length,backend:status.backend,tokensUsed:value.tokensUsed,inferenceTimeMs:value.inferenceTimeMs,gpuExecution:"not exposed"};
 }finally{await client.api("ai-unload");}
}
