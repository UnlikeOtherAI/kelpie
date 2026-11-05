import {readFile,writeFile} from "node:fs/promises";
import {join} from "node:path";
import {validateNetnsEvidence} from "./worker-comparison-netns.mjs";
const dir=process.argv[2];if(!dir)throw Error("EVIDENCE_DIRECTORY_REQUIRED");
const read=async name=>(await readFile(join(dir,name),"utf8")).trim();
const json=async name=>JSON.parse(await read(name));
const queries=JSON.parse(await read("namespace-query-status.json"));
const evidence=validateNetnsEvidence({host:await read("host-netns.txt"),unit:await read("unit-netns.txt"),after:await read("unit-netns-after.txt"),addresses:await json("net-address.json"),routes4:await json("net-routes4.json"),routes6:await json("net-routes6.json"),queries});
await writeFile(join(dir,"namespace-verified.json"),JSON.stringify(evidence),{mode:0o600,flag:"wx"});
