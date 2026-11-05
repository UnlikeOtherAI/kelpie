#!/usr/bin/env node
import assert from "node:assert/strict";
import {readFile,writeFile} from "node:fs/promises";
import {validateWorkerPolicy,verifyWorkerPolicyBinding} from "./worker-comparison-policy.mjs";
const [policyPath,user,reportPath,outputPath]=process.argv.slice(2);
assert.ok(policyPath&&user&&reportPath&&outputPath);
const policy=validateWorkerPolicy(await readFile(policyPath,"utf8"),user);
const report=JSON.parse(await readFile(reportPath,"utf8"));
verifyWorkerPolicyBinding(policy,report,user);
await writeFile(outputPath,JSON.stringify(policy,null,2),{mode:0o600,flag:"wx"});
