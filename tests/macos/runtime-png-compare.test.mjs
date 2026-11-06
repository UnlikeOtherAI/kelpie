import test from "node:test";
import assert from "node:assert/strict";
import {comparisonReason,safeArmFailures} from "./runtime-png-compare.mjs";
const h=n=>n.repeat(64);
const fixture=()=>{
 const cases=["static","noisy","layered"].map((name,i)=>({name,width:10,height:10,rgbaSHA256:h(String(i+1)),alpha:{min:255,max:255,nonopaque:0},viewport:{engine:"chromium",width:900,height:700},pattern:{blue:1,red:2,sampledColors:3}}));
 return Array.from({length:4},()=>({status:{code:0,signal:null},report:{focusedScopePassed:true,ownedChildExited:true,ownedListenersReleased:true,source:"a".repeat(40),executableHash:h("b"),debugLibraryHash:h("c"),cefFrameworkHash:h("d"),engines:[{engine:"chromium",checks:cases.map(x=>({name:"png-equivalence-"+x.name,detail:structuredClone(x)}))}]}}));
};
test("comparison requires exact identity, viewport, alpha and cleanup",()=>{
 assert.equal(comparisonReason(fixture()),null);
 for(const mutate of [r=>delete r[0].report.source,r=>delete r[1].report.cefFrameworkHash,r=>r[2].report.engines[0].checks[1].detail.alpha.min=0,r=>r[3].report.engines[0].checks[0].detail.viewport.width=899,r=>r[0].report.ownedChildExited=false]){const r=fixture();mutate(r);assert.notEqual(comparisonReason(r),null);}
});

test("failure receipt maps untrusted fields to fixed categories",()=>{
 const facts=safeArmFailures({phaseAtFailure:"private-url",engines:[{checks:[{passed:false,name:"png-equivalence-noisy",pixelStage:"decode",code:"PIXEL_LENGTH"},{passed:false,name:"private-page",pixelStage:"private-stage",code:"private-error"}]}]});
 assert.deepEqual(facts,{phase:"other",failure:"none",checks:[{check:"png-equivalence-noisy",stage:"decode",code:"PIXEL_LENGTH"},{check:"other",stage:"other",code:"OTHER"}]});
 assert.equal(JSON.stringify(facts).includes("private"),false);
});
