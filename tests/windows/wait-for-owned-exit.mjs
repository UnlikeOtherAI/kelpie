import assert from "node:assert/strict";
import {execFile} from "node:child_process";
import {promisify} from "node:util";
import {join} from "node:path";
// Wait only for the already pinned original process. Never terminate it or
// mistake a recycled PID for the candidate whose public close was requested.
export async function waitForOwnedExit({pid,executable,startTime},timeoutMs=5000){
 assert.equal(process.platform,"win32");assert.ok(Number.isSafeInteger(pid)&&pid>0);
 assert.ok(typeof executable==="string"&&executable.length<=4096);
 assert.match(startTime,/^\d{4}-\d\d-\d\dT[\d:.]+Z$/);
 assert.ok(Number.isInteger(timeoutMs)&&timeoutMs>=0&&timeoutMs<=5000);
 const quote=value=>"'"+value.replaceAll("'","''")+"'";
 const script="$ErrorActionPreference='Stop';function Same($p){if($null -eq $p){return $false};try{return ([IO.Path]::GetFullPath($p.Path) -ieq [IO.Path]::GetFullPath("+quote(executable)+") -and $p.StartTime.ToUniversalTime().ToString('o') -eq "+quote(startTime)+")}catch{try{if($p.HasExited){return $false}}catch{};throw 'OWNED_PROCESS_INSPECTION_FAILED'}};$watch=[Diagnostics.Stopwatch]::StartNew();$p=Get-Process -Id "+pid+" -ErrorAction SilentlyContinue;if(Same $p){$null=$p.WaitForExit("+timeoutMs+")};$remaining=Get-Process -Id "+pid+" -ErrorAction SilentlyContinue;[pscustomobject]@{exited=(!(Same $remaining));waitedMs=$watch.ElapsedMilliseconds}|ConvertTo-Json";
 const result=await promisify(execFile)(join(process.env.WINDIR,"System32/WindowsPowerShell/v1.0/powershell.exe"),
  ["-NoProfile","-NonInteractive","-OutputFormat","Text","-EncodedCommand",Buffer.from(script,"utf16le").toString("base64")],
  {windowsHide:true,timeout:timeoutMs+5000,maxBuffer:65536});
 const value=JSON.parse(result.stdout.replace(/^\uFEFF/,""));assert.equal(typeof value.exited,"boolean");return value;
}
