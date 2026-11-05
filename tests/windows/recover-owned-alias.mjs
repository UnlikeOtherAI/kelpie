import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { promisify } from "node:util";
import { readFile, writeFile, access, readdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { waitForOwnedExit } from "./wait-for-owned-exit.mjs";

const [exe, cli, privateRoot, reportPath, expectedRevision, expectedCli, expectedBundle, portText = "28420"] = process.argv.slice(2);
assert.ok(exe && cli && privateRoot && reportPath && /^[a-f0-9]{40}$/.test(expectedRevision ?? ""));
assert.match(expectedCli ?? "", /^[a-f0-9]{64}$/); assert.match(expectedBundle ?? "", /^[a-f0-9]{64}$/);
const hash = async file => createHash("sha256").update(await readFile(file)).digest("hex");
assert.equal(await hash(exe), "54c8be31e003853947182c9461755bf4e7be5f91a2c64fcfb97ed5da1a32d755");
assert.equal(await hash(join(dirname(exe), "kelpie.dll")), "231683fbb5f6025caf71d0c32eaaedba1594c09711ea24ebf75fa34478a9c0b3");
assert.equal(await hash(cli), expectedCli);
const bundle = createHash("sha256"), files = (await readdir(dirname(cli))).filter(name => name.endsWith(".js")).sort();
assert.ok(files.length > 0); for (const name of files) bundle.update(name + ":" + await hash(join(dirname(cli), name)) + "\n");
assert.equal(bundle.digest("hex"), expectedBundle);
const exec = promisify(execFile);
assert.equal((await exec("git.exe", ["rev-parse", "HEAD"])).stdout.trim(), expectedRevision);
assert.equal((await exec("git.exe", ["status", "--porcelain", "--untracked-files=no"])).stdout.trim(), "");
const env = { ...process.env, USERPROFILE: privateRoot, KELPIE_HOME: join(privateRoot, "cli-home") };
const alias = "capture-g08-native-5877e6fa-c", port = Number(portText);
assert.ok(Number.isInteger(port) && port > 0 && port < 65536);
const store = async () => JSON.parse(await readFile(join(env.KELPIE_HOME, "browsers.json"), "utf8"));
const run = async args => {
  try { const result = await exec(process.execPath, [cli, ...args], { env, windowsHide: true, timeout: 45000, maxBuffer: 2097152 });
    return JSON.parse(result.stdout); }
  catch (error) { let value; try { value = JSON.parse(String(error.stdout ?? "")); } catch {}
    const safe = new Error("PUBLIC_CLI_FAILED"); safe.code = value?.error?.code ?? null; throw safe; }
};
const ps = async script => JSON.parse((await exec("powershell.exe", ["-NoProfile", "-NonInteractive", "-EncodedCommand", Buffer.from(script, "utf16le").toString("base64")], { env, windowsHide: true, timeout: 15000 })).stdout);
const report = { source: "5877e6fa438385cab6ae44de0343a748d2251053", testRevision: expectedRevision, stage: "stale-stop", checks: [], cleanup: "not-started" };
let active, relaunchRequested = false;
try {
  const original = (await store()).running[alias]; assert.ok(original?.pid && original.launchId && original.readinessFile);
  const stale = await run(["browser", "stop", alias]);
  assert.equal(stale.success, true); assert.equal(stale.alreadyExitedPid, original.pid);
  assert.equal((await store()).running[alias], undefined); await access(original.readinessFile);
  report.checks.push({ name: "original dead launch reconciled", passed: true, pid: original.pid });
  report.stage = "relaunch";
  relaunchRequested = true;
  const launched = await run(["browser", "launch", alias, "--port", String(port)]); assert.equal(launched.success, true);
  active = (await store()).running[alias]; assert.ok(active?.pid && active.launchId && active.readinessFile);
  const identity = await ps("$p=Get-Process -Id " + active.pid + ";$s=Get-NetTCPConnection -State Listen -LocalPort " + port + ";if($s.OwningProcess -ne $p.Id){throw 'listener mismatch'};[pscustomobject]@{pid=$p.Id;path=$p.Path;startTime=$p.StartTime.ToUniversalTime().ToString('o');sessionId=$p.SessionId}|ConvertTo-Json");
  assert.equal(identity.sessionId, 1); assert.equal(identity.path.replaceAll(String.fromCharCode(92), "/").toLowerCase(), exe.replaceAll(String.fromCharCode(92), "/").toLowerCase());
  const readiness = JSON.parse(await readFile(active.readinessFile, "utf8")); assert.equal(readiness.launchId, active.launchId);
  const response = await fetch("http://127.0.0.1:" + port + "/v1/get-device-info", { method: "POST", headers: { authorization: "Bearer " + readiness.token, "content-type": "application/json" }, body: "{}", signal: AbortSignal.timeout(10000) });
  assert.equal(response.ok, true); assert.equal((await response.json()).success, true);
  report.checks.push({ name: "same alias and profile relaunched", passed: true, pid: active.pid });
  report.stage = "stop";
  assert.equal((await run(["browser", "stop", alias])).success, true);
  const exit = await waitForOwnedExit({ pid: active.pid, executable: exe, startTime: identity.startTime });
  assert.equal(exit.exited, true); assert.equal((await store()).running[alias], undefined);
  let absent = false; try { await access(active.readinessFile); } catch { absent = true; }
  assert.equal(absent, true);
  report.checks.push({ name: "relaunched process stopped", passed: true, exit, readinessAbsent: absent });
  report.stage = "complete"; report.cleanup = "public-cli-closed";
} catch (error) {
  report.checks.push({ name: "public recovery", passed: false, stage: report.stage, code: typeof error.code === "string" ? error.code : null });
  process.exitCode = 1;
} finally {
  if (relaunchRequested && report.cleanup !== "public-cli-closed") {
    try { await run(["browser", "stop", alias]); report.cleanup = "public-stop-requested"; }
    catch { report.cleanup = "public-stop-failed"; }
  }
  await writeFile(reportPath, JSON.stringify(report, null, 2), { flag: "wx" });
}