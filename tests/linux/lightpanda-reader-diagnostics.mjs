import assert from "node:assert/strict";

const hidden=["HIDDEN_ATTRIBUTE_LP","HIDDEN_DISPLAY_LP","HIDDEN_INHERITED_LP",
  "HIDDEN_OPACITY_LP","HIDDEN_COLLAPSE_LP"];
function safe(value){
  const serialized=JSON.stringify(value);
  assert.ok(!serialized.includes("CAPTURE_SECRET_"),"Private canary escaped");
  for(const text of hidden)assert.ok(!serialized.includes(text),"Hidden text escaped");
  return serialized;
}
function refs(snapshot,prefix,mode,seenGenerations){
  assert.ok(Array.isArray(snapshot.elements),"REFERENCE_FORMAT_INVALID");
  const values=snapshot.elements.map(element=>element?.ref);
  assert.ok(values.every(ref=>typeof ref==="string"&&ref.length<=128),"REFERENCE_FORMAT_INVALID");
  assert.ok(new Set(values).size===values.length,"REFERENCE_DUPLICATE");
  if(mode==="managed"){
    const matches=values.map(ref=>/^s([1-9][0-9]*)e[1-9][0-9]*$/.exec(ref));
    assert.ok(matches.every(Boolean),"REFERENCE_FORMAT_INVALID");
    const generations=new Set(matches.map(match=>match[1]));
    assert.ok(generations.size<=1,"REFERENCE_GENERATION_MIXED");
    if(generations.size){
      const generation=[...generations][0];
      assert.ok(!seenGenerations.has(generation),"REFERENCE_GENERATION_REUSED");
      seenGenerations.add(generation);
    }
  }else if(mode==="lightpanda")assert.ok(values.every(ref=>/^e[1-9][0-9]*$/.test(ref)),"REFERENCE_FORMAT_INVALID");
  else assert.ok(values.every(ref=>ref.startsWith(prefix)),"REFERENCE_FORMAT_INVALID");
}
/** Real fixed-reader observations only; these checks never widen capabilities. */
export async function runLightpandaReaderDiagnostics({check,read,adversariesInstalled,referencePrefix=value=>value,referenceMode="prefix",selected=["snapshot","extract","status","ready"]}){
  assert.ok(selected.length>0&&new Set(selected).size===selected.length&&selected.every(value=>["snapshot","extract","status","ready"].includes(value)));
  assert.ok(["prefix","lightpanda","managed"].includes(referenceMode));
  const seenGenerations=new Set();
  const passed=Object.fromEntries(selected.map(value=>[value,true]));
  const run=async(kind,name,fn)=>{if(!Object.hasOwn(passed,kind))return;const ok=await check(name,fn);passed[kind]=passed[kind]&&ok;};
  const requireFixture=()=>assert.equal(adversariesInstalled(),true,"Adversarial fixture was not installed");
  await run("snapshot","reader bounded priority snapshot",async()=>{
    requireFixture();
    const snapshot=await read("snapshot",{maxElements:20,maxChars:8000,prioritize:true,prefix:"lp-audit-c-"});
    safe(snapshot);refs(snapshot,referencePrefix("lp-audit-c-"),referenceMode,seenGenerations);
    assert.equal(snapshot.elements.length,20);assert.equal(snapshot.truncated,true);
    assert.deepEqual(snapshot.elements.slice(0,10).map(item=>item.name),
      ["Confirm order","Duplicate action","Duplicate action","Disabled action","Covered action",
        "Remove blocking overlay","Moving action","Start moving target","Stop moving target","Details"]);
    // The limit is filled by priority controls; it does not promise a heading.
    assert.ok(snapshot.text.length<=8000);
    return {elements:snapshot.elements.length,truncated:snapshot.truncated};
  });
  await run("snapshot","reader scoped snapshot and independent references",async()=>{
    requireFixture();
    const snapshot=await read("snapshot",{scope:"#catalogue",maxElements:64,maxChars:8000,
      prioritize:true,prefix:"lp-audit-d-"});
    safe(snapshot);refs(snapshot,referencePrefix("lp-audit-d-"),referenceMode,seenGenerations);
    assert.ok(!snapshot.elements.some(item=>item.name==="Confirm order"));
    for(const name of ["Available products","Green tea","Black tea"])
      assert.ok(snapshot.elements.some(item=>item.name===name),name);
    assert.equal(snapshot.elements.filter(item=>item.role==="link"&&item.name==="Details").length,2);
    return {elements:snapshot.elements.length};
  });
  await run("snapshot","reader text and element budgets",async()=>{
    requireFixture();
    const snapshot=await read("snapshot",{maxElements:5,maxChars:256,prioritize:true,prefix:"lp-audit-e-"});
    safe(snapshot);refs(snapshot,referencePrefix("lp-audit-e-"),referenceMode,seenGenerations);
    assert.ok(snapshot.text.length<=256);assert.ok(snapshot.elements.length<=5);
    assert.equal(snapshot.truncated,true);
    return {elements:snapshot.elements.length,chars:snapshot.text.length,truncated:true};
  });
  await run("extract","reader nested, missing, ambiguous and provenance",async()=>{
    requireFixture();
    const result=await read("extract",{scope:"#catalogue",maxChars:8000,metadata:true,fields:[
      {name:"missing",selector:".not-present",source:"text"},
      {name:"ambiguous",selector:"h3",source:"text"},
      {name:"products",selector:"article",source:"text",multiple:true,fields:[
        {name:"title",selector:"h3",source:"text"},
        {name:"price",selector:".price",source:"text"},
        {name:"link",selector:"a",source:"href"},
      ]},
    ]});
    safe(result);
    assert.equal(result.fields[0].status,"missing");
    assert.equal(result.fields[1].status,"ambiguous");assert.deepEqual(result.fields[1].values,[]);
    const products=result.fields[2];assert.equal(products.status,"ok");
    assert.deepEqual(products.provenance,{selector:"article",source:"text",matches:2});
    assert.equal(products.records.length,2);
    assert.deepEqual(products.records.map(row=>row[0].values[0]),["Green tea","Black tea"]);
    assert.deepEqual(products.records.map(row=>row[1].values[0]),["12.50","9.00"]);
    assert.ok(products.records.every(row=>row[2].provenance.source==="href"));
    assert.deepEqual(result.documentRevision,{availability:"unavailable"});
    assert.ok(result.metadata.some(item=>item.key==="description"&&item.value==="Kelpie catalogue fixture"));
    assert.ok(result.metadata.some(item=>item.key==="name"&&item.value==="Green tea"&&item.attribute.startsWith("json:")));
    assert.ok(result.metadata.every(item=>item.authority==="publisher-claim"&&item.selector&&item.attribute));
    return {records:products.records.length,metadata:result.metadata.length};
  });
  await run("extract","reader extraction budget and private omission",async()=>{
    requireFixture();
    const result=await read("extract",{maxChars:256,metadata:true,fields:[
      {name:"body",selector:"body",source:"text"},{name:"hidden",selector:"#lp-hidden-ready",source:"text"},
    ]});
    safe(result);assert.equal(result.fields[1].status,"missing");
    const total=result.fields.flatMap(field=>field.values).join("").length+
      result.metadata.map(item=>item.value).join("").length;
    assert.ok(total<=256);assert.equal(result.truncated,true);
    return {chars:total,truncated:true};
  });
  await run("status","reader honest page status",async()=>{
    requireFixture();
    const result=await read("status",{});safe(result);
    assert.equal(result.title,"Kelpie capture acceptance");assert.equal(result.documentState,"complete");
    assert.deepEqual(result.network,{availability:"unavailable"});
    assert.deepEqual(result.errors,{availability:"unavailable"});
    assert.ok(Number.isFinite(result.viewport.width)&&Number.isFinite(result.viewport.height));
    return {documentState:result.documentState,network:result.network.availability,errors:result.errors.availability};
  });
  await run("ready","reader unique readiness",async()=>{
    requireFixture();
    const result=await read("ready",{state:"complete",selector:"#unique"});
    assert.equal(result.ready,true);assert.equal(result.visible,true);assert.equal(result.matches,1);
    assert.equal(result.incomplete,false);return {ready:true,matches:1};
  });
  await run("ready","reader hidden, missing and ambiguous readiness",async()=>{
    requireFixture();
    for(const selector of ["#lp-hidden-ready","#lp-opacity-ready","#lp-collapse-ready","#lp-missing-ready"]){
      const result=await read("ready",{state:"complete",selector});
      assert.equal(result.ready,false,selector);
    }
    const duplicate=await read("ready",{state:"complete",selector:"#catalogue h3"});
    assert.equal(duplicate.ready,false);assert.equal(duplicate.matches,2);
    return {refused:5};
  });
  return passed;
}
