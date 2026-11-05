#!/usr/bin/env node
// Isolation-only unit: no browser, worker, fixture data or cost measurement.
import assert from "node:assert/strict";
import {readFile,writeFile} from "node:fs/promises";
import {join,resolve} from "node:path";
import {observeWorkerBoundary,validateProbe} from "./worker-comparison-network.mjs";

assert.ok(typeof process.getuid==="function"&&process.getuid()>0,"NONROOT_REQUIRED");
assert.ok(process.argv[2],"OUTPUT_REQUIRED");
const dir=resolve(process.argv[2]);
const group=(await readFile("/proc/self/cgroup","utf8")).split("\n").find(x=>x.startsWith("0::"))?.slice(3);
assert.ok(group?.startsWith("/"));
const root="/sys/fs/cgroup"+group;
const [memory,cpu,tasks]=await Promise.all(["memory.max","cpu.max","pids.max"].map(
 name=>readFile(join(root,name),"utf8").then(value=>value.trim())));
assert.equal(memory,"2147483648");assert.equal(tasks,"256");
const [quota,period]=cpu.split(/\s+/).map(Number);assert.equal(quota,period);
const observed=await observeWorkerBoundary(process.env.KELPIE_AB_CANARY_HOST??"",
 Number(process.env.KELPIE_AB_CANARY_PORT));
await writeFile(join(dir,"network-observation.json"),JSON.stringify({pid:process.pid,uid:process.getuid(),observed}),{mode:0o600,flag:"wx"});
// Allow the independent launcher to record this live unit and its cgroup.
await new Promise(ok=>setTimeout(ok,1500));
const networkProbe=validateProbe("inside",observed.local,observed.nonlocal);
await writeFile(join(dir,"report.json"),JSON.stringify({pid:process.pid,uid:process.getuid(),
 boundary:{memoryMax:memory,cpuMax:cpu,tasksMax:tasks},networkProbe},null,2),{mode:0o600,flag:"wx"});
