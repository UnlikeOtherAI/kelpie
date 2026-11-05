#!/usr/bin/env node
// A disposable compositor, never the person's GNOME display or accessibility bus.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdir, mkdtemp, chmod, writeFile, readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { randomBytes } from "node:crypto";
const [binaryArg, cliArg, outputArg] = process.argv.slice(2);
assert.equal(process.platform, "linux"); assert.ok(binaryArg && cliArg && outputArg);
const output = resolve(outputArg); await mkdir(output, { recursive: false });
const runtime = await mkdtemp("/tmp/kelpie-wayland-"); await chmod(runtime, 0o700);
const env = { ...process.env, XDG_RUNTIME_DIR: runtime };
for (const key of ["DISPLAY", "WAYLAND_DISPLAY", "WAYLAND_SOCKET", "DBUS_SESSION_BUS_ADDRESS", "AT_SPI_BUS_ADDRESS", "XAUTHORITY"])
  delete env[key];
const socket = "kelpie-" + randomBytes(12).toString("hex");
const client = fileURLToPath(new URL("./isolated-wayland-client.mjs", import.meta.url));
const args = ["--", "/usr/bin/weston", "--backend=headless", "--renderer=pixman", "--shell=kiosk-shell.so",
  "--no-config", "--width=1280", "--height=900", "--socket=" + socket, "--xwayland",
  "--debug", "--debug-scopes=scene-graph", "--log=" + join(output, "weston.log"),
  "--", process.execPath, client, resolve(binaryArg), resolve(cliArg), output];
const child = spawn("/usr/bin/dbus-run-session", args, { env, stdio: ["ignore", "pipe", "pipe"] });
let stdout = "", stderr = "", failure;
child.stdout.setEncoding("utf8"); child.stderr.setEncoding("utf8");
child.stdout.on("data", value => { stdout = (stdout + value).slice(-131072); });
child.stderr.on("data", value => { stderr = (stderr + value).slice(-131072); });
const timer = setTimeout(() => { failure = "Isolated compositor exceeded deadline"; child.kill("SIGTERM"); }, 180000);
try {
  const result = await new Promise((done, reject) => { child.once("error", reject); child.once("exit", (code, signal) => done({ code, signal })); });
  await writeFile(join(output, "compositor-result.json"), JSON.stringify({
    scope: "ISOLATED_WAYLAND", runtime, socket, source: env.KELPIE_CAPTURE_SOURCE,
    testSource: env.KELPIE_TEST_REVISION, result, stdout, stderr, failure }, null, 2));
  assert.equal(result.code, 0, failure ?? stderr);
  assert.equal(JSON.parse(await readFile(join(output, "client-result.json"), "utf8")).success, true,
    "Owned client must positively complete; compositor exit alone is insufficient");
} finally { clearTimeout(timer); }
