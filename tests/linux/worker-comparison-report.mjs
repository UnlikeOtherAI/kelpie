#!/usr/bin/env node
import {readFile,stat} from "node:fs/promises";
import {compareWorkerReceipts} from "./worker-comparison-result.mjs";
const files=process.argv.slice(2);
if(files.length!==2)throw Error("Provide two owned comparison receipts");
async function load(path){
 const info=await stat(path);if(info.size>1048576)throw Error("Receipt exceeds bound");
 return JSON.parse(await readFile(path,"utf8"));
}
const result=compareWorkerReceipts(await load(files[0]),await load(files[1]));
console.log(JSON.stringify(result,null,2));
