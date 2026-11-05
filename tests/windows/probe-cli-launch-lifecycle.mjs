import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { createHash } from "node:crypto";
import { access, mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join } from "node:path";
import { waitForOwnedExit } from "./wait-for-owned-exit.mjs";

const [exe, cli, fixture, privateRoot, reportPath, manifestPath, expectedCli, expectedFixture, expectedRevision, expectedBundle] = process.argv.slice(2);
assert.ok([exe, cli, fixture, privateRoot, reportPath, manifestPath].every(value => value && isAbsolute(value)));
for (const hash of [expectedCli, expectedFixture, expectedBundle]) assert.match(hash ?? "", /^[a-f0-9]{64}$/);
assert.match(expectedRevision ?? "", /^[a-f0-9]{40}$/);
const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
const hash = async file => createHash("sha256").update(await readFile(file)).digest("hex");
assert.equal(await hash(exe), manifest.exeSha256);
assert.equal(await hash(join(dirname(exe), "kelpie.dll")), manifest.dllSha256);
assert.equal(await hash(cli), expectedCli);
const bundleFiles = (await readdir(dirname(cli))).filter(name => name.endsWith(".js")).sort();
assert.ok(bundleFiles.length > 0);
const bundle = createHash("sha256");
for (const name of bundleFiles) bundle.update(name + ":" + await hash(join(dirname(cli), name)) + "\n");
assert.equal(bundle.digest("hex"), expectedBundle);
assert.equal(await hash(fixture), expectedFixture);
const exec = promisify(execFile);
const call = (file, args, timeout = 30000) => exec(file, args, { windowsHide: true, timeout, maxBuffer: 2097152 });
assert.equal((await call("git.exe", ["rev-parse", "HEAD"])).stdout.trim(), expectedRevision);
assert.equal((await call("git.exe", ["status", "--porcelain", "--untracked-files=no"])).stdout.trim(), "");
await mkdir(privateRoot, { recursive: false });
const sidScript = "[Security.Principal.WindowsIdentity]::GetCurrent().User.Value";
const ps = script => call("powershell.exe", ["-NoProfile", "-NonInteractive", "-EncodedCommand", Buffer.from(script, "utf16le").toString("base64")]);
const sid = (await ps(sidScript)).stdout.trim(); assert.match(sid, /^S-1-[0-9-]+$/);
await call(join(process.env.WINDIR, "System32/icacls.exe"), [privateRoot, "/inheritance:r", "/grant:r", "*" + sid + ":(OI)(CI)F", "*S-1-5-18:(OI)(CI)F"]);
const home = join(privateRoot, "home"), fixtureProfile = join(privateRoot, "fixture-profile"), appProfile = join(privateRoot, "app-profile");
await mkdir(home);
const env = { ...process.env, USERPROFILE: privateRoot, KELPIE_HOME: home };
const alias = "capture-cli-lifecycle-" + manifest.source.slice(0, 8);
const report = { source: manifest.source, testRevision: expectedRevision, stage: "register-fixture", checks: [], cleanup: "not-started" };
const run = async args => {
  try { const result = await exec(process.execPath, [cli, ...args], { env, windowsHide: true, timeout: 45000, maxBuffer: 2097152 });
    return { value: JSON.parse(result.stdout), code: 0 }; }
  catch (error) { let value; try { value = JSON.parse(String(error.stdout ?? "")); } catch {}
    return { value, code: typeof error.code === "number" ? error.code : null, signal: error.signal ?? null, killed: error.killed ?? false }; }
};
const store = async () => JSON.parse(await readFile(join(home, "browsers.json"), "utf8"));
let app, candidateRequested = false;
try {
  assert.equal((await run(["browser", "register", alias, "--platform", "windows", "--app-path", fixture, "--profile-dir", fixtureProfile])).value?.success, true);
  report.stage = "unready-launch";
  const failed = await run(["browser", "launch", alias, "--hidden", "--port", "28420"]);
  assert.equal(failed.value?.success, false);
  assert.equal(failed.value?.error?.code, "BROWSER_LAUNCH_FAILED");
  const [pidText, startTime] = (await readFile(join(fixtureProfile, "fixture-process.txt"), "utf8")).trim().split(String.fromCharCode(10));
  const pid = Number(pidText); assert.ok(Number.isSafeInteger(pid) && pid > 0);
  const fixtureExit = await waitForOwnedExit({ pid, executable: fixture, startTime });
  assert.equal(fixtureExit.exited, true); assert.equal((await store()).running[alias], undefined);
  report.checks.push({ name: "unready exact child retired", passed: true, pid, fixtureExit });
  report.stage = "register-candidate";
  assert.equal((await run(["browser", "register", alias, "--platform", "windows", "--app-path", exe, "--profile-dir", appProfile])).value?.success, true);
  report.stage = "retry-candidate";
  candidateRequested = true;
  const launched = await run(["browser", "launch", alias, "--hidden", "--port", "28420"]);
  assert.equal(launched.value?.success, true);
  app = (await store()).running[alias]; assert.ok(app?.pid && app.launchId && app.readinessFile);
  const identity = JSON.parse((await ps("$p=Get-Process -Id " + app.pid + ";$s=Get-NetTCPConnection -State Listen -LocalPort 28420;if($s.OwningProcess -ne $p.Id){throw 'listener mismatch'};[pscustomobject]@{pid=$p.Id;path=$p.Path;startTime=$p.StartTime.ToUniversalTime().ToString('o');sessionId=$p.SessionId}|ConvertTo-Json")).stdout);
  assert.equal(identity.sessionId, 1); assert.equal(identity.path.replaceAll(String.fromCharCode(92), "/").toLowerCase(), exe.replaceAll(String.fromCharCode(92), "/").toLowerCase());
  const readiness = JSON.parse(await readFile(app.readinessFile, "utf8")); assert.equal(readiness.launchId, app.launchId);
  const response = await fetch("http://127.0.0.1:28420/v1/get-device-info", { method: "POST", headers: { authorization: "Bearer " + readiness.token, "content-type": "application/json" }, body: "{}", signal: AbortSignal.timeout(10000) });
  assert.equal(response.ok, true); assert.equal((await response.json()).success, true);
  report.checks.push({ name: "public retry reached owned listener", passed: true, pid: app.pid, sessionId: identity.sessionId });
  report.stage = "stop";
  assert.equal((await run(["browser", "stop", alias])).value?.success, true);
  const appExit = await waitForOwnedExit({ pid: app.pid, executable: exe, startTime: identity.startTime });
  assert.equal(appExit.exited, true); assert.equal((await store()).running[alias], undefined);
  let readinessAbsent = false; try { await access(app.readinessFile); } catch { readinessAbsent = true; }
  assert.equal(readinessAbsent, true);
  report.checks.push({ name: "public stop retired owned candidate", passed: true, appExit, readinessAbsent });
  report.cleanup = "public-cli-closed"; report.stage = "complete";
} catch (error) {
  report.checks.push({ name: "lifecycle", passed: false, stage: report.stage, category: error.code === "ERR_ASSERTION" ? "assertion" : "operation-failed" });
  process.exitCode = 1;
} finally {
  if (candidateRequested && report.cleanup !== "public-cli-closed") {
    const stopped = await run(["browser", "stop", alias]); report.cleanup = stopped.value?.success ? "public-stop-requested" : "public-stop-failed";
  }
  await writeFile(reportPath, JSON.stringify(report, null, 2), { flag: "wx" });
}