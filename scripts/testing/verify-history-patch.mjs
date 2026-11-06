import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {execFile} from "node:child_process";
import {mkdir,readFile,writeFile} from "node:fs/promises";
import {join,resolve} from "node:path";
import {promisify} from "node:util";
import {pathToFileURL} from "node:url";

export const allowedPaths=[
 "docs/api/browser-control.md",
 "packages/shared/src/browser-control/history.ts",
 "packages/shared/src/browser-control/managed-session.ts",
 "packages/shared/src/browser-control/playwright.ts",
 "packages/shared/tests/playwright-history.test.ts",
];
const hash=bytes=>createHash("sha256").update(bytes).digest("hex");
export function decodePinnedPatch(value,expected){
 assert.ok(typeof value==="string"&&value.length>0&&value.length<=24000&&/^[A-Za-z0-9+/]*={0,2}$/.test(value),"PATCH_INPUT_INVALID");
 const bytes=Buffer.from(value,"base64");
 assert.ok(bytes.length>0&&bytes.length<=20000&&bytes.toString("base64")===value,"PATCH_INPUT_INVALID");
 assert.equal(hash(bytes),expected,"PATCH_HASH_MISMATCH");return bytes;
}
export function verifyPatchPaths(output){
 const lines=output.trim().split("\n");
 assert.equal(lines.length,allowedPaths.length,"PATCH_PATHS_INVALID");
 const paths=lines.map(line=>{
  const fields=line.split("\t");
  assert.ok(fields.length===3&&/^\d+$/.test(fields[0])&&/^\d+$/.test(fields[1]),"PATCH_PATHS_INVALID");
  return fields[2];
 });
 assert.deepEqual([...paths].sort(),[...allowedPaths].sort(),"PATCH_PATHS_INVALID");
}
export function verifyStatusPaths(output){
 const lines=output.trimEnd().split("\n");
 assert.equal(lines.length,allowedPaths.length,"POSTAPPLY_PATHS_INVALID");
 const paths=lines.map(line=>{
  assert.ok(/^( M|M |\?\?) /.test(line),"POSTAPPLY_PATHS_INVALID");
  return line.slice(3);
 });
 assert.deepEqual(paths.sort(),[...allowedPaths].sort(),"POSTAPPLY_PATHS_INVALID");
}
export function verifyFileHashes(actual,expected){
 assert.deepEqual(Object.keys(actual).sort(),[...allowedPaths].sort(),"FILE_PATHS_INVALID");
 for(const path of allowedPaths)assert.equal(actual[path],expected[path],"FILE_HASH_MISMATCH");
}
async function main(){
 const base="22e616cfed21074cffef1e0d557645db6e895a28";
 const root=resolve(process.argv[2]),scratch=resolve(process.argv[3]),exec=promisify(execFile);
 const expected={
  "docs/api/browser-control.md":process.env.HISTORY_DOC_SHA,
  "packages/shared/src/browser-control/history.ts":process.env.HISTORY_IMPL_SHA,
  "packages/shared/src/browser-control/managed-session.ts":process.env.HISTORY_SESSION_SHA,
  "packages/shared/src/browser-control/playwright.ts":process.env.HISTORY_PLAYWRIGHT_SHA,
  "packages/shared/tests/playwright-history.test.ts":process.env.HISTORY_TEST_SHA,
 };
 assert.match(process.env.HISTORY_PATCH_SHA??"",/^[a-f0-9]{64}$/);
 for(const path of allowedPaths)assert.match(expected[path]??"",/^[a-f0-9]{64}$/);
 const bytes=decodePinnedPatch(process.env.HISTORY_PATCH_B64,process.env.HISTORY_PATCH_SHA);
 assert.equal((await exec("git",["rev-parse","HEAD"],{cwd:root})).stdout.trim(),base,"BASE_MISMATCH");
 assert.equal((await exec("git",["status","--porcelain","--untracked-files=all"],{cwd:root})).stdout.trim(),"","DIRTY_BASE");
 await mkdir(scratch,{recursive:true,mode:0o700});const patch=join(scratch,"candidate.patch");
 await writeFile(patch,bytes,{mode:0o600,flag:"wx"});
 const numstat=await exec("git",["apply","--numstat",patch],{cwd:root});verifyPatchPaths(numstat.stdout);
 await exec("git",["apply","--check",patch],{cwd:root});
 await exec("git",["apply",patch],{cwd:root});
 const actual={};for(const path of allowedPaths)actual[path]=hash(await readFile(join(root,path)));
 verifyFileHashes(actual,expected);
 const status=(await exec("git",["status","--porcelain","--untracked-files=all"],{cwd:root})).stdout;
 verifyStatusPaths(status);
 await writeFile(join(scratch,"patch-verification.json"),JSON.stringify({version:1,base,patchSha256:process.env.HISTORY_PATCH_SHA,verifiedFiles:allowedPaths.length,verified:true}),{mode:0o600,flag:"wx"});
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
 main().catch(()=>{process.stderr.write("HISTORY_PATCH_VERIFICATION_FAILED\n");process.exitCode=1;});
}
