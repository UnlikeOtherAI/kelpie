import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync, mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
if (process.argv[2] === "--child") {
  const command = "$ErrorActionPreference='Stop';$p=Get-Process -Id $PID;try{$p.ProcessorAffinity=3}catch{};try{$p.PriorityClass='AboveNormal'}catch{};$p.Refresh();if($p.ProcessorAffinity.ToInt64()-ne1 -or [string]$p.PriorityClass-ne'Normal'){exit 7};Write-Output 'HARD_JOB_POLICY_PASS'";
  const result = execFileSync("powershell.exe", ["-NoProfile", "-Command", command], { encoding: "utf8", timeout: 4000 });
  assert.match(result, /HARD_JOB_POLICY_PASS/); console.log("descendant reset attempts remained mask1/Normal");
} else {
  assert.equal(process.platform, "win32");
  const output = resolve(process.argv[2]); mkdirSync(output, { recursive: true });
  const report = resolve(output, "job-harmless.json"), log = resolve(output, "job-harmless.log");
  execFileSync(process.execPath, ["scripts/testing/windows-confined-process.mjs", report, log, "10000",
    process.execPath, fileURLToPath(import.meta.url), "--child"], { stdio: "inherit", timeout: 15000 });
  assert.equal(JSON.parse(readFileSync(report, "utf8")).exitCode, 0);
  assert.match(readFileSync(log, "utf8"), /descendant reset attempts/);
  console.log("hard JobObject affinity/priority regression passed");
}
