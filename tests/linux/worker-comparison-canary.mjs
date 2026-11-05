#!/usr/bin/env node
import assert from "node:assert/strict";
import {createServer} from "node:net";
import {writeFile} from "node:fs/promises";
import {probeWorkerBoundary} from "./worker-comparison-network.mjs";

const [mode,a,b]=process.argv.slice(2);
assert.ok(typeof process.getuid==="function"&&process.getuid()!==0,"Canary must run as non-root");
if(mode==="serve"){
 const server=createServer(socket=>socket.destroy());
 await new Promise((ok,bad)=>{server.once("error",bad);server.listen(0,"0.0.0.0",ok);});
 await writeFile(a,JSON.stringify({port:server.address().port}),{mode:0o600,flag:"wx"});
 process.once("SIGTERM",()=>server.close());
}else if(mode==="outside"){
 const result=await probeWorkerBoundary(a,Number(b),"outside");
 console.log(JSON.stringify(result));
}else throw Error("Unknown canary mode");
