import assert from "node:assert/strict";
import {test} from "node:test";
import {artifactFacts,errorFacts,playFacts,toolEnvelopeFacts} from "./runtime-diagnostics.mjs";

test("diagnostics retain bounded failure structure without page values",()=>{
 const secret="SECRET-PAGE-VALUE";
 const error={name:"ZodError",cause:{code:"UND_ERR_SOCKET",message:secret},
  stack:"Error: "+secret+"\n at f (/runner/work/tests/macos/runtime-client.mjs:91:10)\n at x (/private/"+secret+":1:1)",
  issues:[{code:"invalid_type",path:["width"]},{code:"unrecognized_keys",path:[secret],keys:[secret]}]};
 const facts=errorFacts(error);
 assert.equal(facts.causeCode,"UND_ERR_SOCKET");
 assert.deepEqual(facts.locations,[{file:"runtime-client.mjs",line:91}]);
 assert.equal(facts.issues[1].path[0],"OTHER");
 const response=playFacts({success:true,runId:secret,outputs:{catalogue:{fields:[{status:"ok",values:[secret],provenance:{selector:secret}}]}},
  artifacts:[{id:secret,mimeType:"image/gif",width:10,height:10,byteLength:20,[secret]:secret}]});
 assert.equal(response.artifactCount,1);assert.equal(response.extraction.valueCount,1);
 assert.equal(response.artifacts[0].unknownKeyCount,1);
 const failure=artifactFacts({success:false,error:{code:"ARTIFACT_NOT_FOUND",message:secret}});
 assert.equal(failure.success,false);assert.equal(failure.errorCode,"ARTIFACT_NOT_FOUND");
 const tool=toolEnvelopeFacts({result:{content:[{type:"text",text:secret}]}});
 assert.ok(!JSON.stringify({facts,response,tool,failure}).includes(secret));
});