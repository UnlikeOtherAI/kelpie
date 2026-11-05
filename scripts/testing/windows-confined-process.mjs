import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { writeFile } from "node:fs/promises";

assert.equal(process.platform, "win32", "Windows JobObject utility only");
const [reportPath, logPath, timeoutText, executable, ...args] = process.argv.slice(2);
assert.ok(reportPath && logPath && executable, "report log timeout executable [args]");
const timeout = Number(timeoutText);
assert.ok(Number.isInteger(timeout) && timeout >= 100 && timeout <= 1800000);
const source = resolve(dirname(fileURLToPath(import.meta.url)), "windows-confined-process.cs");
const request = Buffer.from(JSON.stringify({ source, executable: resolve(executable), args,
  directory: process.cwd(), log: resolve(logPath), timeout }), "utf8").toString("base64");
const script = "$ErrorActionPreference='Stop';$self=Get-Process -Id $PID;$self.ProcessorAffinity=1;$self.PriorityClass='Normal';$r=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('" + request +
  "'))|ConvertFrom-Json;Add-Type -Path $r.source;$code=[KelpieConfinedProcess]::Run($r.executable,[string[]]$r.args,$r.directory,$r.log,$r.timeout);exit $code";
const started = Date.now();
const child = spawn("powershell.exe", ["-NoProfile", "-Command", script], { windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
let errors = "";
child.stdout.resume();
child.stderr.on("data", data => { if (errors.length < 8192) errors += data; });
const code = await new Promise((resolve, reject) => { child.once("error", reject); child.once("exit", resolve); });
await writeFile(reportPath, JSON.stringify({ version: 1, affinityMask: 1, priority: "Normal",
  breakaway: false, suspendedAssignment: true, killOnClose: true, jobMemoryBytes: 2147483648, timeoutMs: timeout,
  wallMs: Date.now() - started, exitCode: code, launcherFailure: code !== 0 ? errors : undefined }, null, 2), { flag: "wx" });
process.exitCode = code ?? 125;
