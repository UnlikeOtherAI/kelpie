import test from "node:test";import assert from "node:assert/strict";import {safeWgcDiagnostic} from "./wgc-safe-diagnostic.mjs";
test("retains only allowlisted helper failures and clocks",()=>{const r=safeWgcDiagnostic("WGC_STAGE raw-write 12\nWGC_API_FAILURE stage=frame-surface-query -1\nSYNTHETIC_SECRET");assert.equal(r.error,"WGC_API_FAILURE");assert.equal(r.apiStage,"frame-surface-query");assert.deepEqual(r.stages,[{stage:"raw-write",tick:12}]);assert.ok(!JSON.stringify(r).includes("SYNTHETIC_SECRET"));assert.equal(safeWgcDiagnostic("WGC_WINDOW_IDENTITY_MISMATCH").error,"WGC_WINDOW_IDENTITY_MISMATCH");});

test("retains fixed stage names containing digits",()=>{assert.equal(safeWgcDiagnostic("WGC_API_FAILURE stage=d3d11-device-create -1").apiStage,"d3d11-device-create");});

test("drops unrecognized API stage data",()=>{const r=safeWgcDiagnostic("WGC_API_FAILURE stage=secret-token-123 -1");assert.equal(r.error,"WGC_API_FAILURE");assert.equal(r.apiStage,null);assert.ok(!JSON.stringify(r).includes("secret-token-123"));});

test("reports a hidden owned window without labelling it an identity mismatch",()=>{assert.equal(safeWgcDiagnostic("WGC_WINDOW_HIDDEN").error,"WGC_WINDOW_HIDDEN");});
