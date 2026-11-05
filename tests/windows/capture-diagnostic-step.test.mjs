import test from "node:test";
import assert from "node:assert/strict";
import {captureDiagnosticStep} from "./capture-diagnostic-step.mjs";
test("records bounded step facts without preserving exception or result text",async()=>{
 const report={steps:[]};
 assert.equal(await captureDiagnosticStep(report,"tabs",async()=>"private result"),"private result");
 await assert.rejects(captureDiagnosticStep(report,"navigate",async()=>{throw new Error("private URL/token");}));
 assert.equal(report.steps.length,2);assert.equal(report.steps[0].passed,true);
 assert.equal(report.steps[1].passed,false);assert.equal(report.steps[1].kind,"Error");
 assert.ok(report.steps.every(step=>Number.isFinite(step.elapsedMs)&&step.elapsedMs>=0));
 assert.ok(!JSON.stringify(report).includes("private"));
 await assert.rejects(captureDiagnosticStep(report,"unrecognized",async()=>{}),/INVALID_DIAGNOSTIC_STEP/);
});
