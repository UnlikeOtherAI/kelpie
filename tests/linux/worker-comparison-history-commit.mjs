// Experimental branch only: patch one disposable CLI build, never tracked source or a published bundle.
import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {readFile,readdir,stat,writeFile} from "node:fs/promises";
import {fileURLToPath,pathToFileURL} from "node:url";
import {join,resolve} from "node:path";
const expectedSource="1f04401c9cc99bbe515733d0e24fa503964b5c4eb942c9bf8452e2918f34e199";
const original='await page.goBack({ waitUntil: "domcontentloaded", timeout });';
const replacement='await page.goBack({ waitUntil: "commit", timeout });';
const forward='await page.goForward({ waitUntil: "domcontentloaded", timeout });';
const hash=text=>createHash("sha256").update(text).digest("hex");
export function transformHistoryBuild(source,chunks,expected=expectedSource){
 const sourceHash=hash(source.replaceAll("\r\n","\n"));assert.equal(sourceHash,expected,"SOURCE_MISMATCH");
 assert.ok(Array.isArray(chunks)&&chunks.length>0&&chunks.length<=256,"CHUNKS_INVALID");
 const matches=chunks.flatMap((chunk,index)=>Array(chunk.text.split(original).length-1).fill(index));
 assert.equal(matches.length,1,"COMPILED_MATCH_COUNT");
 const index=matches[0],compiled=chunks[index].text;
 assert.equal(compiled.includes(replacement),false,"ALREADY_PATCHED");
 assert.equal(compiled.split(forward).length,2,"FORWARD_MISMATCH");
 const result=compiled.replace(original,replacement);
 return {index,result,receipt:{version:1,sourceSha256:sourceHash,beforeSha256:hash(compiled),
  afterSha256:hash(result),chunk:chunks[index].name,changed:"tab.back-only"}};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
 const root=fileURLToPath(new URL("../..",import.meta.url)),receipt=process.argv[2];
 assert.ok(receipt,"RECEIPT_REQUIRED");
 const source=await readFile(root+"/packages/shared/src/browser-control/playwright.ts","utf8");
 const dist=root+"/packages/cli/dist",names=(await readdir(dist)).filter(name=>name.endsWith(".js"));
 assert.ok(names.length>0&&names.length<=256,"CHUNKS_INVALID");
 const chunks=await Promise.all(names.map(async name=>{
  const file=join(dist,name),info=await stat(file);assert.ok(info.isFile()&&info.size<=10000000,"CHUNK_INVALID");
  return {name,text:await readFile(file,"utf8")};
 }));
 const patched=transformHistoryBuild(source,chunks);
 await writeFile(join(dist,chunks[patched.index].name),patched.result);
 await writeFile(receipt,JSON.stringify(patched.receipt,null,2),{mode:0o600,flag:"wx"});
}
