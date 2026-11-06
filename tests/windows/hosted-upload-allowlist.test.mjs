import {test} from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";

function uploadPaths(workflow){
 const section=workflow.split("name: kelpie-windows-hosted-public-g08")[1]?.split("if-no-files-found:")[0];
 assert.ok(section);const content=section.split("path: |")[1];assert.ok(content);
 return content.split(/\r?\n/).filter(line=>line.trim()).map(line=>{
  const match=/^\s+\$\{\{ runner\.temp \}\}\/([^\r\n]+)$/.exec(line);
  assert.ok(match,"Unexpected upload path");return match[1];
 });
}
test("hosted upload lists only exact synthetic evidence paths",async()=>{
 const workflow=await readFile(".github/workflows/windows.yml","utf8");
 const paths=uploadPaths(workflow);
 const evidence=["manifest.json","diagnostic.json","hosted-spawn.json","hosted-cleanup.json",
  "hosted/c-events.json","hosted/capture-failure.json","hosted/oracle-input.json","hosted/oracle-output.json","hosted/*.gif","hosted/*.mp4"];
 const expected=["kelpie-hosted-g08-preflight/preflight.json",...evidence.map(file=>"kelpie-hosted-g08-evidence/"+file),
  "kelpie-hosted-png-ab/pair.json","kelpie-hosted-png-ab/outcome.json"];
 for(const arm of ["control","candidate"]){
  expected.push("kelpie-hosted-png-ab/"+arm+"/kelpie-hosted-g08-preflight/preflight.json");
  expected.push(...evidence.map(file=>"kelpie-hosted-png-ab/"+arm+"/kelpie-hosted-g08-evidence/"+file));
 }
 assert.deepEqual([...paths].sort(),expected.sort());
 for(const path of paths)assert.doesNotMatch(path,/(?:private|profile|cache|\.out|\.err|\.log|\.\.|\*\*)/i);
});
test("refuses a path outside the anchored runner temp allowlist",async()=>{
 const workflow=await readFile(".github/workflows/windows.yml","utf8");
 const injected=workflow.replace("if-no-files-found: warn","            C:/unexpected/private.txt\n          if-no-files-found: warn");
 assert.throws(()=>uploadPaths(injected),/Unexpected upload path/);
});
