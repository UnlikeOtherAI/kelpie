#!/usr/bin/env node
import assert from "node:assert/strict";
import {readFile,writeFile} from "node:fs/promises";
import {validateWorkerPolicy,verifyWorkerObservationBinding} from "./worker-comparison-policy.mjs";
const [policyPath,user,observationPath,outputPath]=process.argv.slice(2);
assert.ok(policyPath&&user&&observationPath&&outputPath);
const policy=validateWorkerPolicy(await readFile(policyPath,"utf8"),user);
const observation=JSON.parse(await readFile(observationPath,"utf8"));
const observed=verifyWorkerObservationBinding(policy,observation,user);
// This receipt binds facts; it never interprets a failed probe as isolation.
const {network,...policyFacts}=policy;
await writeFile(outputPath,JSON.stringify({policy:{...policyFacts,configuredNetwork:network},observed},null,2),{mode:0o600,flag:"wx"});
