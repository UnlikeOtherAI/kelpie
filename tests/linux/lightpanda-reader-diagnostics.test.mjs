import test from "node:test";
import assert from "node:assert/strict";
import {runLightpandaReaderDiagnostics} from "./lightpanda-reader-diagnostics.mjs";
function fixture({leak=false,badReady=false}={}){
  return async (kind,options)=>{
    if(kind==="snapshot"){
      const names=options.scope?["Available products","Green tea","Black tea","Details","Details"]:
        ["Confirm order","Duplicate action","Duplicate action","Disabled action","Covered action",
          "Remove blocking overlay","Moving action","Start moving target","Stop moving target","Details",
          ...Array(10).fill("button")];
      const elements=names.slice(0,options.maxElements).map((name,i)=>({
        name,role:name==="Details"?"link":"button",ref:options.prefix+(i+1)}));
      return {elements,text:leak?"CAPTURE_SECRET_TEST":"public",truncated:!options.scope};
    }
    if(kind==="extract"){
      const provenance={selector:"article",source:"text",matches:2};
      if(options.scope)return {fields:[{status:"missing"},{status:"ambiguous",values:[]},
        {status:"ok",provenance,records:[
          [{values:["Green tea"]},{values:["12.50"]},{provenance:{source:"href"}}],
          [{values:["Black tea"]},{values:["9.00"]},{provenance:{source:"href"}}],
        ]}],documentRevision:{availability:"unavailable"},truncated:false,metadata:[
          {key:"description",value:"Kelpie catalogue fixture",selector:"meta",attribute:"content",authority:"publisher-claim"},
          {key:"name",value:"Green tea",selector:"script",attribute:"json:/name",authority:"publisher-claim"},
        ]};
      return {fields:[{values:["public"]},{status:"missing"}],metadata:[],truncated:true};
    }
    if(kind==="status")return {title:"Kelpie capture acceptance",documentState:"complete",
      network:{availability:"unavailable"},errors:{availability:"unavailable"},viewport:{width:640,height:480}};
    if(options.selector==="#unique")return {ready:true,visible:true,matches:1,incomplete:false};
    if(options.selector==="#catalogue h3")return {ready:false,matches:2};
    return {ready:badReady};
  };
}
async function run(read,installed=true){
  const checks=[];
  const check=async(name,fn)=>{try{await fn();checks.push({name,passed:true});return true}
    catch(error){checks.push({name,passed:false});return false}};
  return {result:await runLightpandaReaderDiagnostics({check,read,adversariesInstalled:()=>installed}),checks};
}
test("reader qualification requires all positive and refusal checks",async()=>{
  const {result,checks}=await run(fixture());
  assert.deepEqual(result,{snapshot:true,extract:true,status:true,ready:true});
  assert.equal(checks.length,8);assert.ok(checks.every(check=>check.passed));
});
test("privacy leaks, false readiness and missing adversary installation fail closed",async()=>{
  assert.equal((await run(fixture({leak:true}))).result.snapshot,false);
  assert.equal((await run(fixture({badReady:true}))).result.ready,false);
  assert.deepEqual((await run(fixture(),false)).result,{snapshot:false,extract:false,status:false,ready:false});
});

test("qualification reports only explicitly selected candidates",async()=>{
  const checks=[];const check=async(name,fn)=>{await fn();checks.push(name);return true};
  const result=await runLightpandaReaderDiagnostics({check,read:fixture(),adversariesInstalled:()=>true,selected:["status"]});
  assert.deepEqual(result,{status:true});assert.equal(checks.length,1);
  await assert.rejects(()=>runLightpandaReaderDiagnostics({check,read:fixture(),adversariesInstalled:()=>true,selected:["snapshot","snapshot"]}));
});
